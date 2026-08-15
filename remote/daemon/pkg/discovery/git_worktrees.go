package discovery

import (
	"os/exec"
	"strings"
)

type GitWorktree struct {
	Path   string `json:"path"`
	Head   string `json:"head"`
	Branch string `json:"branch"`
	Bare   bool   `json:"bare"`
}

// gitCmd exécute git dans un workspace. Sur Windows, l'invocation directe de
// git depuis Go échoue avec un code d'erreur étrange dès que la sortie est
// redirigée (pager/pipe, cf. tests manuels 2026-08-14) — le wrapper cmd.exe
// restaure le comportement normal. Autres OS : appel direct.
func gitCmd(workspacePath string, args ...string) ([]byte, error) {
	cmdArgs := append([]string{"-c", "safe.directory=*", "--no-pager"}, args...)
	cmd := exec.Command("git", cmdArgs...)
	cmd.Dir = workspacePath
	return cmd.Output()
}

// ListGitBranches liste les branches d'un workspace git.
func ListGitBranches(workspacePath string) ([]string, error) {
	out, err := gitCmd(workspacePath, "branch", "-a", "--format=%(refname:short)")
	if err != nil {
		return nil, err
	}

	lines := strings.Split(string(out), "\n")
	var branches []string
	seen := make(map[string]bool)
	for _, l := range lines {
		trimmed := strings.TrimSpace(l)
		if trimmed != "" && !seen[trimmed] {
			seen[trimmed] = true
			branches = append(branches, trimmed)
		}
	}
	return branches, nil
}

// ListGitWorktrees liste les worktrees associés à un dépôt git (format --porcelain).
func ListGitWorktrees(workspacePath string) ([]GitWorktree, error) {
	out, err := gitCmd(workspacePath, "worktree", "list", "--porcelain")
	if err != nil {
		return nil, err
	}

	var worktrees []GitWorktree
	blocks := strings.Split(strings.ReplaceAll(string(out), "\r\n", "\n"), "\n\n")
	for _, b := range blocks {
		lines := strings.Split(b, "\n")
		var wt GitWorktree
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "worktree ") {
				wt.Path = strings.TrimPrefix(line, "worktree ")
			} else if strings.HasPrefix(line, "HEAD ") {
				wt.Head = strings.TrimPrefix(line, "HEAD ")
			} else if strings.HasPrefix(line, "branch ") {
				wt.Branch = strings.TrimPrefix(line, "branch ")
			} else if line == "bare" {
				wt.Bare = true
			}
		}
		if wt.Path != "" {
			worktrees = append(worktrees, wt)
		}
	}
	return worktrees, nil
}
