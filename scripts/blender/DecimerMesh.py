# ALLEGER UN MODELE TROP LOURD POUR ROBLOX, sans ouvrir Blender.
#
# POURQUOI. Roblox refuse un MeshPart au-dela de 10 000 TRIANGLES. Un modele d'artiste en compte couramment des
# centaines de milliers : il faut le decimer avant l'import, sinon l'upload echoue ou Roblox le simplifie lui-meme,
# n'importe comment.
#
# CE QU'IL FAIT : ouvre le fichier, reduit CHAQUE objet du meme facteur jusqu'a tenir dans le budget demande,
# triangule, et reexporte en FBX pret pour Roblox.
#
# UTILISATION (depuis le dossier du projet) :
#
#   "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python \
#       scripts/blender/DecimerMesh.py -- --input "C:/chemin/oiseau.fbx" --budget 2000
#
# Sans --output, il ecrit a cote du fichier d'origine, suffixe `_light.fbx`. L'original n'est JAMAIS touche.
#
# --budget est un nombre de TRIANGLES pour le modele entier. Reperes : un decor lointain 500-1500, un objet qu'on
# regarde de pres 2000-5000, jamais plus de 10 000 (la limite de Roblox).

import argparse
import os
import sys

import bpy


def parse_args():
    # Blender avale ses propres arguments : les notres sont ceux qui suivent le `--`.
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True, help="fichier a alleger (.fbx, .obj, .glb, .gltf, .blend)")
    p.add_argument("--output", default=None, help="FBX a ecrire (defaut : <input>_light.fbx)")
    p.add_argument("--budget", type=int, default=2000, help="triangles vises pour le modele entier")
    p.add_argument("--keep-shape", action="store_true",
                   help="decime en PLANAIRE plutot qu en COLLAPSE : garde les faces plates, "
                        "utile pour du batiment, mauvais pour de l organique")
    return p.parse_args(argv)


def load(path):
    """Ouvre le fichier dans une scene VIDE. Chaque format a son operateur, et leurs noms ont change selon les
    versions de Blender : on essaie, et on dit clairement ce qui manque plutot que de planter sur une trace."""
    ext = os.path.splitext(path)[1].lower()
    if ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=path)
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".obj":
        # Renomme en 4.x : l ancien `import_scene.obj` n existe plus.
        if hasattr(bpy.ops.wm, "obj_import"):
            bpy.ops.wm.obj_import(filepath=path)
        else:
            bpy.ops.import_scene.obj(filepath=path)
    elif ext == ".dae":
        bpy.ops.wm.collada_import(filepath=path)
    else:
        raise SystemExit(f"[Decimer] Format non gere : {ext}")


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def triangle_count(objects):
    """Le VRAI nombre de triangles, apres evaluation des modificateurs deja presents sur le modele. Compter les
    faces brutes mentirait sur un modele qui porte deja un Subdivision ou un Mirror."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    total = 0
    for obj in objects:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        # Une face a N cotes donne N-2 triangles.
        total += sum(max(len(p.vertices) - 2, 0) for p in mesh.polygons)
        evaluated.to_mesh_clear()
    return total


def triangulate(objects):
    """AVANT de decimer : le Decimate en COLLAPSE travaille sur des triangles de toute facon, et Roblox triangule
    a l import. Le faire nous-memes rend le compte previsible."""
    for obj in objects:
        modifier = obj.modifiers.new(name="LeafiaTriangulate", type="TRIANGULATE")
        modifier.keep_custom_normals = True


def decimate(objects, ratio, keep_shape):
    for obj in objects:
        if keep_shape:
            modifier = obj.modifiers.new(name="LeafiaDecimate", type="DECIMATE")
            modifier.decimate_type = "DISSOLVE"
            # L angle sous lequel deux faces sont considerees comme coplanaires.
            modifier.angle_limit = 0.0873  # 5 degres
        else:
            modifier = obj.modifiers.new(name="LeafiaDecimate", type="DECIMATE")
            modifier.decimate_type = "COLLAPSE"
            modifier.ratio = ratio


def apply_all(objects):
    for obj in objects:
        bpy.context.view_layer.objects.active = obj
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)


def main():
    args = parse_args()
    if not os.path.isfile(args.input):
        raise SystemExit(f"[Decimer] Fichier introuvable : {args.input}")

    load(args.input)
    objects = meshes()
    if not objects:
        raise SystemExit("[Decimer] Aucun mesh dans ce fichier.")

    triangulate(objects)
    before = triangle_count(objects)
    print(f"[Decimer] {len(objects)} objet(s), {before} triangles au depart.")

    if before <= args.budget:
        print("[Decimer] Deja sous le budget : rien a decimer, on reexporte tel quel.")
        ratio = 1.0
    else:
        # LE MEME FACTEUR POUR TOUS : decimer chaque objet a un nombre FIXE de triangles ecraserait les petites
        # pieces (un oeil, un bec) pour sauver les grandes. Proportionnellement, chacun garde son importance.
        ratio = args.budget / before
        print(f"[Decimer] Reduction a {ratio * 100:.1f} % pour viser {args.budget} triangles.")
        decimate(objects, ratio, args.keep_shape)

    apply_all(objects)
    after = triangle_count(meshes())
    print(f"[Decimer] {after} triangles apres coup.")
    if after > 10000:
        print("[Decimer] ATTENTION : au-dessus de 10 000, Roblox refusera ce mesh. Baisse le budget.")

    out = args.output or os.path.splitext(args.input)[0] + "_light.fbx"
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(
        filepath=out,
        use_selection=True,
        # Roblox lit le FBX en metres et applique sa propre echelle : on part d une echelle NEUTRE plutot que de
        # laisser Blender ecrire un facteur que l import multipliera ensuite.
        global_scale=1.0,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_NONE",
        bake_space_transform=True,
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        path_mode="COPY",
        embed_textures=True,
    )
    print(f"[Decimer] Ecrit : {out}")


main()
