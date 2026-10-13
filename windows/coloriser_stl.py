#!/usr/bin/env python3
"""
Colorise un dossier entier de fichiers STL non colorises, automatiquement,
via l'API Meshy (Retexture puis Multi-Color Print), et sort un .3mf pret a
trancher pour chaque fichier.

PAS TESTE PAR CLAUDE : ce script appelle une vraie API payante (credits
Meshy), impossible a tester sans une vraie cle API et de vrais credits a
depenser. Contrairement aux lecteurs RFID de ce projet, il n'a pas ete
verifie en conditions reelles avant livraison - teste-le d'abord sur UN
SEUL fichier avant de lancer un gros dossier, pour verifier que tout se
passe comme prevu avant de depenser des credits sur plusieurs figurines.

Usage :
    python coloriser_stl.py --dossier ./mes_stl --prompt "couleurs naturelles et coherentes"

Variables d'environnement :
    MESHY_API_KEY   ta cle API (recuperee sur meshy.ai/settings/api)

Documentation officielle utilisee pour écrire ce script :
    https://docs.meshy.ai/en/api/retexture
    https://docs.meshy.ai/en/api/multi-color-print
"""

import argparse
import base64
import os
import sys
import time
from pathlib import Path

import requests

BASE_URL = "https://api.meshy.ai/openapi/v1"
INTERVALLE_POLL_SECONDES = 5
TIMEOUT_TACHE_SECONDES = 20 * 60  # 20 minutes max par etape, au cas ou une tache reste bloquee


def en_tetes(cle_api: str) -> dict:
    return {"Authorization": f"Bearer {cle_api}"}


def attendre_tache(url_tache: str, cle_api: str, libelle: str) -> dict:
    """Interroge une tache Meshy jusqu'a SUCCEEDED/FAILED/CANCELED, ou abandonne apres le timeout."""
    debut = time.monotonic()
    while True:
        if time.monotonic() - debut > TIMEOUT_TACHE_SECONDES:
            raise TimeoutError(f"{libelle} : pas de reponse apres {TIMEOUT_TACHE_SECONDES // 60} min")

        reponse = requests.get(url_tache, headers=en_tetes(cle_api), timeout=30)
        reponse.raise_for_status()
        tache = reponse.json()
        statut = tache.get("status")

        if statut == "SUCCEEDED":
            return tache
        if statut in ("FAILED", "CANCELED"):
            message_erreur = (tache.get("task_error") or {}).get("message", "raison inconnue")
            raise RuntimeError(f"{libelle} a echoue : {message_erreur}")

        progres = tache.get("progress", 0)
        print(f"    {libelle} : {statut} ({progres}%)...")
        time.sleep(INTERVALLE_POLL_SECONDES)


def coloriser_un_fichier(chemin_stl: Path, prompt: str, cle_api: str, dossier_sortie: Path,
                          max_couleurs: int, style_couleur: str, marque_imprimante: str) -> None:
    print(f"\n=== {chemin_stl.name} ===")

    taille_mo = chemin_stl.stat().st_size / (1024 * 1024)
    if taille_mo > 50:
        print(f"  ATTENTION : fichier de {taille_mo:.1f} Mo, la limite Meshy est de 50 Mo - risque d'echec.")

    # --- Etape 1 : Retexture (ajoute une vraie texture IA sur le modele uploade) ---
    octets_stl = chemin_stl.read_bytes()
    data_uri = "data:application/octet-stream;base64," + base64.b64encode(octets_stl).decode("ascii")

    print("  Envoi a l'API Retexture...")
    reponse = requests.post(
        f"{BASE_URL}/retexture",
        headers={**en_tetes(cle_api), "Content-Type": "application/json"},
        json={
            "model_url": data_uri,
            "text_style_prompt": prompt,
            "enable_original_uv": False,  # modele tiers, pas genere par Meshy -> on laisse Meshy deplier les UV
        },
        timeout=120,
    )
    reponse.raise_for_status()
    id_retexture = reponse.json()["result"]

    tache_retexture = attendre_tache(f"{BASE_URL}/retexture/{id_retexture}", cle_api, "Retexture")
    print(f"  Retexture terminee ({tache_retexture.get('consumed_credits', '?')} credits).")

    # --- Etape 2 : Multi-Color Print (reduit la texture a N couleurs, exporte en .3mf) ---
    print("  Envoi a l'API Multi-Color Print...")
    reponse = requests.post(
        f"{BASE_URL}/print/multi-color",
        headers={**en_tetes(cle_api), "Content-Type": "application/json"},
        json={
            "input_task_id": id_retexture,  # enchaine directement sur le resultat de l'etape 1
            "max_colors": max_couleurs,
            "style": style_couleur,
            "printer_brand": marque_imprimante,
        },
        timeout=120,
    )
    reponse.raise_for_status()
    id_impression = reponse.json()["result"]

    tache_impression = attendre_tache(f"{BASE_URL}/print/multi-color/{id_impression}", cle_api, "Multi-Color Print")
    print(f"  Multi-Color Print terminee ({tache_impression.get('consumed_credits', '?')} credits).")

    # --- Telechargement du resultat ---
    url_3mf = tache_impression["model_urls"]["3mf"]
    chemin_sortie = dossier_sortie / (chemin_stl.stem + "_colorise.3mf")
    reponse = requests.get(url_3mf, timeout=120)
    reponse.raise_for_status()
    chemin_sortie.write_bytes(reponse.content)
    print(f"  -> Enregistre : {chemin_sortie}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dossier", required=True, help="Dossier contenant les fichiers .stl a coloriser")
    parser.add_argument("--prompt", required=True, help="Description du style/des couleurs voulues")
    parser.add_argument("--sortie", default=None, help="Dossier de sortie (defaut : <dossier>/colorise)")
    parser.add_argument("--couleurs", type=int, default=4, help="Nombre de couleurs max (1-16, defaut 4)")
    parser.add_argument("--style", choices=["realistic", "cartoon"], default="cartoon",
                         help="'cartoon' = zones de couleur unies (recommande pour l'AMS), "
                              "'realistic' = degrade fin mais fichier plus lourd. Defaut : cartoon")
    parser.add_argument("--imprimante", default="bambu",
                         help="Marque pour le profil du slicer integre au 3mf "
                              "(bambu, anycubic, creality, elegoo, flashforge, prusa, qidi, snapmaker, ankermake)")
    args = parser.parse_args()

    cle_api = os.environ.get("MESHY_API_KEY")
    if not cle_api:
        sys.exit("Erreur : variable d'environnement MESHY_API_KEY manquante. "
                 "Recupere ta cle sur meshy.ai/settings/api puis :\n"
                 "  export MESHY_API_KEY=ta_cle_ici   (Mac/Linux)\n"
                 "  set MESHY_API_KEY=ta_cle_ici      (Windows cmd)")

    dossier = Path(args.dossier)
    if not dossier.is_dir():
        sys.exit(f"Erreur : {dossier} n'est pas un dossier valide.")

    fichiers_stl = sorted(dossier.glob("*.stl")) + sorted(dossier.glob("*.STL"))
    if not fichiers_stl:
        sys.exit(f"Aucun fichier .stl trouve dans {dossier}")

    dossier_sortie = Path(args.sortie) if args.sortie else dossier / "colorise"
    dossier_sortie.mkdir(parents=True, exist_ok=True)

    print(f"{len(fichiers_stl)} fichier(s) a traiter, sortie dans {dossier_sortie}\n")

    reussites, echecs = [], []
    for chemin_stl in fichiers_stl:
        try:
            coloriser_un_fichier(chemin_stl, args.prompt, cle_api, dossier_sortie,
                                  args.couleurs, args.style, args.imprimante)
            reussites.append(chemin_stl.name)
        except Exception as e:
            print(f"  ECHEC sur {chemin_stl.name} : {e}")
            echecs.append((chemin_stl.name, str(e)))
            # on continue avec les fichiers suivants plutot que de tout arreter

    print(f"\n=== Bilan : {len(reussites)} reussite(s), {len(echecs)} echec(s) ===")
    for nom, erreur in echecs:
        print(f"  ECHEC {nom} : {erreur}")


if __name__ == "__main__":
    main()
