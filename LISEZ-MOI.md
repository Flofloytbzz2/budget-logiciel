# Objectif Prix pour iPhone

Appli SwiftUI (iOS 16 ou plus). Mêmes fonctions que la version Linux : plusieurs objectifs, prix relevé sur idealo, graphique, épargne avec ajout/retrait et historique, alerte de baisse de prix, date d'achat estimée, et un onglet **Compte** pour synchroniser avec ton PC.

Tu n'as pas de Mac : GitHub compile l'appli pour toi et te donne le fichier `.ipa`.

## 1. Compiler l'.ipa avec GitHub (gratuit)

1. Envoie le contenu du dossier dans ton dépôt GitHub (voir « Mettre à jour » plus bas si c'est déjà fait).
2. Onglet **Actions** : la compilation démarre toute seule (5 à 10 minutes).
3. Quand la pastille est verte, ouvre l'exécution et télécharge **ObjectifPrix-ipa** en bas de page. C'est un zip qui contient `ObjectifPrix.ipa`.

Si la compilation échoue (croix rouge) : ouvre le job `build`, cherche `error:` dans « Search logs » et envoie-moi les lignes.

## 2. Mettre à jour l'appli (ajout de l'onglet Compte)

Dans le dépôt, ouvre le dossier **ObjectifPrix**, puis « Add file > Upload files », et glisse les 6 fichiers du dossier `a-envoyer` :
`AccountView.swift`, `Sync.swift` (nouveaux) et `Models.swift`, `Store.swift`, `RootView.swift`, `ObjectifPrixApp.swift` (remplacés). Clique sur « Commit changes » : une nouvelle compilation démarre, puis réinstalle le nouvel `.ipa` avec AltStore.

## 3. Synchroniser iPhone et PC (onglet Compte)

Il faut faire ça une seule fois sur chaque appareil :

1. Onglet **Compte** (iPhone) ou « Compte » en bas de la barre latérale (PC).
2. Touche « Créer mon jeton GitHub » : GitHub ouvre la page de création d'un jeton déjà réglé sur la permission « gist ».
3. Mets **No expiration** dans Expiration, puis « Generate token » tout en bas.
4. Copie le jeton (il commence par `ghp_`), colle-le dans l'appli et touche « Se connecter ».

Utilise le même compte GitHub sur les deux appareils : le premier crée le fichier en ligne, le second le retrouve tout seul.

- La synchro se fait à l'ouverture de l'appli, quelques secondes après chaque modification, et toutes les 10 minutes sur PC.
- Si tu modifies le même objectif sur les deux appareils en même temps, la modification la plus récente gagne.
- Les données sont dans un « gist secret » de ton compte GitHub : pas listé publiquement, mais lisible par quiconque aurait son lien. Il ne contient que les noms, prix et montants.
- Le jeton est dans le trousseau de l'iPhone, et dans un fichier réservé à toi (`~/.config/objectif-prix/account.json`) sur PC.

## 4. Bon à savoir

- Le prix est relevé à chaque ouverture de l'appli si le dernier relevé date de plus de 24 h. En arrière-plan, iOS décide seul de l'heure : ce n'est pas garanti tous les jours.
- Si idealo bloque la lecture, utilise « Prix manuel » (menu ⋯ d'un objectif).
- Autorise les notifications au premier lancement pour recevoir les alertes de baisse.
