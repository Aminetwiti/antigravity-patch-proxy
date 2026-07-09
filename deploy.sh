#!/bin/bash
# Script de déploiement automatisé pour Linux
# Génère les dossiers de distribution pour ag-doctor-ui

echo "Démarrage de la génération du build pour le déploiement..."
cd ag-doctor-ui || exit 1

echo "Installation des dépendances et compilation de l'interface..."
npm run dist:dir

if [ $? -eq 0 ]; then
    echo "=============================================="
    echo "Succès ! Le build a été généré dans ag-doctor-ui/release/"
    echo "=============================================="
else
    echo "=============================================="
    echo "Erreur lors de la génération du build."
    echo "=============================================="
    exit 1
fi
