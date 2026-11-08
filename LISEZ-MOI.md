# Objectif Prix pour iPhone

Appli SwiftUI (iOS 16 ou plus). Mêmes fonctions que la version Linux : plusieurs objectifs, prix relevé sur idealo, graphique, épargne avec ajout/retrait et historique, alerte de baisse de prix, date d'achat estimée.

Tu n'as pas de Mac : GitHub compile l'appli pour toi et te donne le fichier `.ipa`.

## 1. Compiler l'.ipa avec GitHub (gratuit)

1. Crée un compte sur github.com si tu n'en as pas.
2. Crée un nouveau dépôt (bouton « New »), nom : `objectif-prix`. Public, c'est le plus simple.
3. Sur la page du dépôt vide, clique sur **uploading an existing file**, puis glisse **tout le contenu** du dossier décompressé :
   `ObjectifPrix/`, `project.yml`, `.gitignore` et le dossier caché `.github/`.
   - Dans le gestionnaire de fichiers de Mint, `Ctrl + H` affiche les fichiers cachés.
   - Si GitHub ne prend pas le dossier `.github`, fais « Add file > Create new file », tape `.github/workflows/build.yml` comme nom, et colle le contenu du fichier.
4. Clique sur **Commit changes**.
5. Onglet **Actions** : la compilation démarre toute seule (5 à 10 minutes). Tu peux aussi la relancer avec « Construire l'IPA > Run workflow ».
6. Quand la pastille est verte, ouvre l'exécution et télécharge **ObjectifPrix-ipa** en bas de page. C'est un zip qui contient `ObjectifPrix.ipa`.

Si la compilation échoue (croix rouge) : ouvre l'exécution, copie les lignes d'erreur en rouge et envoie-les-moi, je corrige.

## 2. Installer sur l'iPhone depuis Linux

AltServer officiel n'existe que pour Windows et macOS. Sous Linux, des outils communautaires font le travail :

- **iloader** : installe SideStore sur l'iPhone depuis Linux. SideStore renouvelle ensuite lui-même la signature sur le téléphone.
- **Sideloader** (Dadoum) et **Impactor** : installent directement un `.ipa` depuis Linux.

Dans tous les cas :
- Il faut ton identifiant Apple (le compte gratuit suffit). Avec un compte gratuit, la signature expire au bout de **7 jours** : il faut la renouveler (automatique avec SideStore).
- Active le **Mode développeur** sur l'iPhone : Réglages > Confidentialité et sécurité > Mode développeur.
- Branche l'iPhone en USB la première fois.

## 3. Bon à savoir

- Le prix est relevé à chaque ouverture de l'appli si le dernier relevé date de plus de 24 h. En arrière-plan, iOS décide seul de l'heure : ce n'est pas garanti tous les jours.
- Si idealo bloque la lecture, utilise « Prix manuel » (menu ⋯ d'un objectif).
- Les données restent sur le téléphone. Il n'y a pas de synchronisation avec la version Linux.
- Autorise les notifications au premier lancement pour recevoir les alertes de baisse.
