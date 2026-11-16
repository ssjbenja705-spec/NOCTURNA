-- Pegar en la barra de comandos de Studio (Ctrl+Enter). Deja el monstruo final de
-- Meshy, con su esqueleto y su textura, en
-- ReplicatedStorage.NocturnaAssets.OrganismoRig (lo anima ChaseCreature.lua).
--
-- MODEL: id del modelo subido desde assets/models/organismo/meshy/ElOrganismoRig.fbx.
-- COLOR / NORMAL / ROUGHNESS: ids de las tres imágenes de esa misma carpeta.
local MODEL = 128771559250205
local COLOR = 135094894866550
local NORMAL = 110057460127565
local ROUGHNESS = 127859122747577

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local loaded = game:GetService("InsertService"):LoadAsset(MODEL)
local mesh = loaded:FindFirstChildWhichIsA("MeshPart", true)
assert(mesh, "el modelo no trae una MeshPart")
local bones = 0
for _, item in ipairs(mesh:GetDescendants()) do
	if item:IsA("Bone") then
		bones += 1
	end
end

local assets = ReplicatedStorage:FindFirstChild("NocturnaAssets") or Instance.new("Folder")
assets.Name = "NocturnaAssets"
assets.Parent = ReplicatedStorage
local previous = assets:FindFirstChild("OrganismoRig")
if previous then
	previous:Destroy()
end

for _, child in ipairs(mesh:GetChildren()) do
	if child:IsA("SurfaceAppearance") then
		child:Destroy()
	end
end
mesh.Name = "OrganismoRig"
mesh.TextureID = ""
mesh.Material = Enum.Material.Slate
mesh.Color = Color3.fromRGB(120, 60, 60)
mesh.Anchored = true
mesh.CanCollide = false
mesh.CanQuery = false
mesh.CanTouch = false
mesh.CastShadow = false
mesh:SetAttribute("BoneCount", bones)
local surface = Instance.new("SurfaceAppearance")
surface.ColorMap = "rbxassetid://" .. COLOR
surface.NormalMap = "rbxassetid://" .. NORMAL
surface.RoughnessMap = "rbxassetid://" .. ROUGHNESS
surface.Parent = mesh
mesh.Parent = assets
loaded:Destroy()

print("[OrganismoRig] huesos:", bones, "tamaño:", mesh.Size, "padre:", mesh.Parent:GetFullName())
