package discovery

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

var (
	ErrLockedOut  = errors.New("trop de tentatives échouées, temporairement verrouillé")
	ErrInvalidPIN = errors.New("code PIN invalide")
	ErrExpiredPIN = errors.New("code PIN expiré")
)

type SessionInfo struct {
	DeviceID        string    `json:"deviceId"`
	Name            string    `json:"name,omitempty"`
	AllowedProjects []string  `json:"allowedProjects,omitempty"`
	CreatedAt       time.Time `json:"createdAt"`
	ExpiresAt       time.Time `json:"expiresAt"`
	// Admin : appareil administrateur (r�vocation des autres devices).
	// Seul le premier appairage d'un device (ou un appel explicite) peut
	// l'activer : un device ne peut jamais se promouvoir via /pair.
	Admin bool `json:"admin,omitempty"`
	// IP : adresse d'origine du device (extractIP(remoteAddr) au pairing).
	IP string `json:"ip,omitempty"`
}

type attemptRecord struct {
	count       int
	lockedUntil time.Time
}

// PairingManager gère l'appairage par code PIN éphémère 6 chiffres (P4).
// Il génère un PIN à durée de vie courte (60s), échange le PIN valide contre
// un jeton de session cryptographique (256 bits), et protège contre les
// attaques par force brute avec un verrouillage exponentiel/durée fixe après 5 échecs.
type PairingManager struct {
	mu              sync.RWMutex
	currentPIN      string
	pinExpiresAt    time.Time
	pinTTL          time.Duration
	sessions        map[string]SessionInfo
	attempts        map[string]*attemptRecord
	maxAttempts     int
	lockoutDuration time.Duration
	sessionTTL      time.Duration
}

func NewPairingManager() *PairingManager {
	pm := &PairingManager{
		pinTTL:          60 * time.Second,
		sessions:        make(map[string]SessionInfo),
		attempts:        make(map[string]*attemptRecord),
		maxAttempts:     5,
		lockoutDuration: 5 * time.Minute,
		sessionTTL:      30 * 24 * time.Hour, // session 30 jours
	}
	pm.GeneratePIN()
	return pm
}

// GeneratePIN génère un nouveau code à 6 chiffres aléatoire cryptographique.
func (pm *PairingManager) GeneratePIN() string {
	pm.mu.Lock()
	defer pm.mu.Unlock()

	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		pm.currentPIN = ""
		return ""
	}
	pm.currentPIN = fmt.Sprintf("%06d", n.Int64())
	pm.pinExpiresAt = time.Now().Add(pm.pinTTL)
	return pm.currentPIN
}

// CurrentPIN retourne le PIN actif et sa durée de validité restante.
// Si le PIN est expiré, un nouveau PIN est automatiquement généré.
func (pm *PairingManager) CurrentPIN() (string, time.Duration) {
	pm.mu.Lock()
	defer pm.mu.Unlock()

	if time.Now().After(pm.pinExpiresAt) || pm.currentPIN == "" {
		n, err := rand.Int(rand.Reader, big.NewInt(1000000))
		if err != nil {
			pm.currentPIN = ""
			return "", 0
		}
		pm.currentPIN = fmt.Sprintf("%06d", n.Int64())
		pm.pinExpiresAt = time.Now().Add(pm.pinTTL)
	}
	return pm.currentPIN, time.Until(pm.pinExpiresAt)
}

// VerifyPIN valide le PIN soumis par un client (identifié par ip / deviceId).
// En cas de succès, génère un jeton de session cryptographique et reset les tentatives.
// allowedProjects (optionnel) restreint le device aux projets donnés (scope 3.3).
func (pm *PairingManager) VerifyPIN(remoteAddr, pin, deviceID string, allowedProjects ...[]string) (string, time.Time, error) {
	ip := extractIP(remoteAddr)

	pm.mu.Lock()
	defer pm.mu.Unlock()

	var allowed []string
	if len(allowedProjects) > 0 {
		allowed = allowedProjects[0]
	}

	now := time.Now()

	// 1. Vérification anti-brute-force
	rec := pm.attempts[ip]
	if rec != nil {
		if now.Before(rec.lockedUntil) {
			return "", time.Time{}, fmt.Errorf("%w (réessayez dans %v)", ErrLockedOut, time.Until(rec.lockedUntil).Round(time.Second))
		}
		if now.After(rec.lockedUntil) && rec.count >= pm.maxAttempts {
			// Verrouillage expiré : reset
			delete(pm.attempts, ip)
			rec = nil
		}
	}

	// 2. Vérification de l'expiration du PIN
	if now.After(pm.pinExpiresAt) {
		return "", time.Time{}, ErrExpiredPIN
	}

	// 3. Comparaison en temps constant pour éviter les attaques temporelles
	match := subtle.ConstantTimeCompare([]byte(strings.TrimSpace(pin)), []byte(pm.currentPIN)) == 1

	if !match {
		if rec == nil {
			rec = &attemptRecord{}
			pm.attempts[ip] = rec
		}
		rec.count++
		if rec.count >= pm.maxAttempts {
			rec.lockedUntil = now.Add(pm.lockoutDuration)
			return "", time.Time{}, fmt.Errorf("%w : %d tentatives échouées, verrouillé pendant %v", ErrLockedOut, rec.count, pm.lockoutDuration)
		}
		return "", time.Time{}, fmt.Errorf("%w (%d/%d tentatives restantes)", ErrInvalidPIN, pm.maxAttempts-rec.count, pm.maxAttempts)
	}

	// 4. Succès : reset des tentatives et génération du token de session
	delete(pm.attempts, ip)

	tokenBytes := make([]byte, 32)
	if _, err := io.ReadFull(rand.Reader, tokenBytes); err != nil {
		return "", time.Time{}, fmt.Errorf("erreur de génération de jeton: %w", err)
	}
	token := hex.EncodeToString(tokenBytes)
	expiresAt := now.Add(pm.sessionTTL)

	pm.sessions[token] = SessionInfo{
		DeviceID:        deviceID,
		Name:            "",
		AllowedProjects: allowed,
		CreatedAt:       now,
		ExpiresAt:       expiresAt,
		Admin:           pm.hasSessionLocked(deviceID),
		IP:              ip,
	}

	// Régénérer un nouveau PIN immédiatement après un appairage réussi
	n, _ := rand.Int(rand.Reader, big.NewInt(1000000))
	pm.currentPIN = fmt.Sprintf("%06d", n.Int64())
	pm.pinExpiresAt = now.Add(pm.pinTTL)

	return token, expiresAt, nil
}

// ValidateSession retourne les infos de session si le jeton est valide et non
// expiré. Retourne (SessionInfo{}, false) sinon. C'est l'équivalent enrichi de
// ValidateToken : le gateway en a besoin pour filtrer par projet (3.3).
func (pm *PairingManager) ValidateSession(token string) (SessionInfo, bool) {
	if token == "" {
		return SessionInfo{}, false
	}
	pm.mu.RLock()
	defer pm.mu.RUnlock()

	sess, ok := pm.sessions[token]
	if !ok {
		return SessionInfo{}, false
	}
	if !time.Now().Before(sess.ExpiresAt) {
		return SessionInfo{}, false
	}
	return sess, true
}

// RevokeDevice invalide tous les jetons de session d'un device donné (équivalent
// removeDevice du backend Node). Retourne false si aucun jeton n'a été révoqué.
func (pm *PairingManager) RevokeDevice(deviceID string) bool {
	pm.mu.Lock()
	defer pm.mu.Unlock()

	revoked := false
	for token, sess := range pm.sessions {
		if sess.DeviceID == deviceID {
			delete(pm.sessions, token)
			revoked = true
		}
	}
	return revoked
}

// hasSessionLocked rapporte si un device poss�de d�j� une session active
// (lock d�tenu). Le premier appairage d'un device devient administrateur.
func (pm *PairingManager) hasSessionLocked(deviceID string) bool {
	if deviceID == "" {
		return false
	}
	now := time.Now()
	for _, sess := range pm.sessions {
		if sess.DeviceID == deviceID && now.Before(sess.ExpiresAt) {
			return true
		}
	}
	return false
}

// ListSessions retourne la liste des sessions actives (pour /admin/devices).
func (pm *PairingManager) ListSessions() []SessionInfo {
	pm.mu.RLock()
	defer pm.mu.RUnlock()

	now := time.Now()
	out := make([]SessionInfo, 0, len(pm.sessions))
	for _, sess := range pm.sessions {
		if now.Before(sess.ExpiresAt) {
			out = append(out, sess)
		}
	}
	return out
}

// ValidateToken vérifie si un jeton de session est valide et non expiré.
func (pm *PairingManager) ValidateToken(token string) bool {
	if token == "" {
		return false
	}
	pm.mu.RLock()
	defer pm.mu.RUnlock()

	sess, ok := pm.sessions[token]
	if !ok {
		return false
	}
	return time.Now().Before(sess.ExpiresAt)
}

// HTTPHandler expose l'endpoint de pairing pour le client mobile (POST /pair).
func (pm *PairingManager) HTTPHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		if r.Method == http.MethodGet {
			// Sécurité : le PIN ne doit jamais être exposé via HTTP (uniquement console hôte)
			http.Error(w, `{"error":"Méthode non autorisée"}`, http.StatusMethodNotAllowed)
			return
		}

		if r.Method == http.MethodDelete {
			// Sécurité (VULN-07) : la révocation exige une authentification session valide.
			token := r.URL.Query().Get("token")
			if token == "" {
				authHeader := r.Header.Get("Authorization")
				token = strings.TrimPrefix(authHeader, "Bearer ")
			}
			if !pm.ValidateToken(token) {
				w.WriteHeader(http.StatusUnauthorized)
				json.NewEncoder(w).Encode(map[string]string{"error": "Authentification requise"})
				return
			}

			// Révocation d'un device : DELETE /pair?deviceId=xxx (admin hôte).
			deviceID := r.URL.Query().Get("deviceId")
			if deviceID == "" {
				http.Error(w, `{"error":"deviceId requis"}`, http.StatusBadRequest)
				return
			}
			if pm.RevokeDevice(deviceID) {
				json.NewEncoder(w).Encode(map[string]interface{}{"status": "revoked", "deviceId": deviceID})
			} else {
				json.NewEncoder(w).Encode(map[string]interface{}{"status": "not_found", "deviceId": deviceID})
			}
			return
		}

		if r.Method != http.MethodPost {
			http.Error(w, `{"error":"Méthode non autorisée"}`, http.StatusMethodNotAllowed)
			return
		}

		var req struct {
			PIN             string   `json:"pin"`
			DeviceID        string   `json:"deviceId"`
			Name            string   `json:"name,omitempty"`
			AllowedProjects []string `json:"allowedProjects,omitempty"`
		}
		if err := json.NewDecoder(io.LimitReader(r.Body, 4096)).Decode(&req); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(map[string]string{"error": "Corps JSON invalide"})
			return
		}

		token, expiresAt, err := pm.VerifyPIN(r.RemoteAddr, req.PIN, req.DeviceID, req.AllowedProjects)
		if err != nil {
			status := http.StatusUnauthorized
			if errors.Is(err, ErrLockedOut) || strings.Contains(err.Error(), ErrLockedOut.Error()) {
				status = http.StatusTooManyRequests
			}
			w.WriteHeader(status)
			json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
			return
		}

		// On stocke aussi le nom du device (utile pour le futur /admin/devices).
		pm.mu.Lock()
		if sess, ok := pm.sessions[token]; ok {
			sess.Name = req.Name
			pm.sessions[token] = sess
		}
		pm.mu.Unlock()

		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"token":     token,
			"expiresAt": expiresAt.Format(time.RFC3339),
			"status":    "paired",
		})
	}
}

func extractIP(addr string) string {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return addr
	}
	return host
}
