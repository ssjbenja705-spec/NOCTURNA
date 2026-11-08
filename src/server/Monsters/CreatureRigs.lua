-- Generado por assets/blender/rig_creatures.py: no editar a mano.
-- Esqueletos de las criaturas (assets/models/rigged). Height: alto total de la
-- malla en studs; Feet: altura de los pies respecto de la raíz; Hips: dónde está
-- el hueso Hips respecto de la raíz (por si el importador descarta el hueso Root,
-- que no pesa vértices); Span: distancia de Hips a Head (MonsterFactory corrige
-- con ella la escala del importado); HeadSize: largo del hueso Head; Bones:
-- huesos que trae el FBX.
return {
    ElColoso = {Height = 9.0000, Feet = -5.5000, Hips = Vector3.new(0.0000, -1.1619, 0.3874),
        Span = 3.7049, HeadSize = 0.7237, Triangles = 17375,
        Bones = {"Root", "Hips", "Spine1", "Spine2", "Chest", "Neck", "Head", "LeftClavicle", "LeftUpperArm", "LeftForearm", "LeftHand", "LeftFingers1", "LeftFingers2", "LeftThigh", "LeftShin", "LeftFoot", "LeftToe", "RightClavicle", "RightUpperArm", "RightForearm", "RightHand", "RightFingers1", "RightFingers2", "RightThigh", "RightShin", "RightFoot", "RightToe", "PlateLeft", "PlateRight", "PlateBack"}},
    ElImitador = {Height = 7.2000, Feet = -3.2000, Hips = Vector3.new(0.0000, 0.9025, 0.1884),
        Span = 2.4756, HeadSize = 0.7473, Triangles = 17459,
        Bones = {"Root", "Hips", "Spine1", "Spine2", "Chest", "Neck", "Head", "LeftClavicle", "LeftUpperArm", "LeftForearm", "LeftHand", "LeftFingers1", "LeftFingers2", "LeftThigh", "LeftShin", "LeftFoot", "LeftToe", "RightClavicle", "RightUpperArm", "RightForearm", "RightHand", "RightFingers1", "RightFingers2", "RightThigh", "RightShin", "RightFoot", "RightToe", "Jaw"}},
    ElOyente = {Height = 8.4000, Feet = -4.0000, Hips = Vector3.new(0.0000, 0.8174, 0.4346),
        Span = 2.9179, HeadSize = 0.8379, Triangles = 17459,
        Bones = {"Root", "Hips", "Spine1", "Spine2", "Chest", "Neck", "Head", "LeftClavicle", "LeftUpperArm", "LeftForearm", "LeftHand", "LeftFingers1", "LeftFingers2", "LeftThigh", "LeftShin", "LeftFoot", "LeftToe", "RightClavicle", "RightUpperArm", "RightForearm", "RightHand", "RightFingers1", "RightFingers2", "RightThigh", "RightShin", "RightFoot", "RightToe"}},
    ElQuieto = {Height = 7.2000, Feet = -3.6000, Hips = Vector3.new(0.0000, 0.0530, 0.0954),
        Span = 2.9034, HeadSize = 0.6485, Triangles = 17459,
        Bones = {"Root", "Hips", "Spine1", "Spine2", "Chest", "Neck", "Head", "LeftClavicle", "LeftUpperArm", "LeftForearm", "LeftHand", "LeftFingers1", "LeftFingers2", "LeftThigh", "LeftShin", "LeftFoot", "LeftToe", "RightClavicle", "RightUpperArm", "RightForearm", "RightHand", "RightFingers1", "RightFingers2", "RightThigh", "RightShin", "RightFoot", "RightToe"}},
    ElTrepador = {Height = 7.0000, Feet = -3.5000, Hips = Vector3.new(0.0000, -0.0085, 0.2899),
        Span = 2.1417, HeadSize = 1.3323, Triangles = 17459,
        Bones = {"Root", "Hips", "Spine1", "Spine2", "Spine3", "Chest", "Neck", "Head", "LeftClavicle", "LeftUpperArm", "LeftForearm", "LeftHand", "LeftFingers1", "LeftFingers2", "LeftThigh", "LeftShin", "LeftFoot", "LeftToe", "RightClavicle", "RightUpperArm", "RightForearm", "RightHand", "RightFingers1", "RightFingers2", "RightThigh", "RightShin", "RightFoot", "RightToe", "Abdomen"}},
}
