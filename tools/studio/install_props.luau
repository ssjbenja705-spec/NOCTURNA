-- Pegar en la barra de comandos de Studio (Ctrl+Enter) para armar
-- ServerStorage.NocturnaProps con las mallas de Blender.
--
-- ASSET: id del modelo subido desde assets/models/props/NocturnaProps.fbx.
-- COMMIT: commit de GitHub donde está assets/models/props/props.json.
--
-- Cada MeshPart del FBX se llama "<Objeto>__<Grupo>". Este script las agrupa en un
-- Model por objeto y les pone lo que dice props.json: material, color,
-- transparencia, colisión, textura de carne (SurfaceAppearance), luz y burbujas.
-- Si el importador las dejó mirando hacia atrás (la canilla del dispenser detrás
-- del cuerpo), las gira media vuelta.
local ASSET = 0
local COMMIT = "main"

local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

local SURFACES = {
	OrganismoFlesh = {
		ColorMap = "rbxassetid://120753309483474",
		NormalMap = "rbxassetid://82475769405359",
		RoughnessMap = "rbxassetid://110891094884569",
	},
	OrganismoPlate = {
		ColorMap = "rbxassetid://124341745303686",
		NormalMap = "rbxassetid://85701142822629",
		RoughnessMap = "rbxassetid://110840020343864",
	},
}

-- Las piezas del monstruo final no son utilería: van a
-- ReplicatedStorage.NocturnaAssets.Organismo (las arma ChaseCreature en el cliente).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = ReplicatedStorage:FindFirstChild("NocturnaAssets") or Instance.new("Folder")
assets.Name = "NocturnaAssets"
assets.Parent = ReplicatedStorage
local creature = nil

local was = HttpService.HttpEnabled
HttpService.HttpEnabled = true
local url = "https://raw.githubusercontent.com/ssjbenja705-spec/NOCTURNA/" .. COMMIT .. "/assets/models/props/props.json"
local manifest = HttpService:JSONDecode(HttpService:GetAsync(url))
HttpService.HttpEnabled = was

local loaded = InsertService:LoadAsset(ASSET)
-- Se arma de cero: no quedan piezas de una versión anterior del modelo.
local stale = ServerStorage:FindFirstChild("NocturnaProps")
if stale then
	stale:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "NocturnaProps"
folder.Parent = ServerStorage

local function rgb(list)
	return Color3.fromRGB(list[1], list[2], list[3])
end

local done, skipped = 0, {}
for _, piece in ipairs(loaded:GetDescendants()) do
	if piece:IsA("MeshPart") then
		local prop, group = piece.Name:match("^(.-)__(.+)$")
		local spec = prop and manifest[prop] and manifest[prop][group]
		if spec then
			local model = folder:FindFirstChild(prop)
			if prop == "Organismo" then
				if not creature then
					local previous = assets:FindFirstChild("Organismo")
					if previous then
						previous:Destroy()
					end
					creature = Instance.new("Model")
					creature.Name = "Organismo"
					creature.Parent = assets
				end
				model = creature
			elseif not model then
				model = Instance.new("Model")
				model.Name = prop
				model.Parent = folder
			end
			local old = model:FindFirstChild(group)
			if old then
				old:Destroy()
			end
			for _, child in ipairs(piece:GetChildren()) do
				if child:IsA("SurfaceAppearance") or child:IsA("Light") or child:IsA("ParticleEmitter") then
					child:Destroy()
				end
			end
			piece.Name = group
			piece.TextureID = ""
			piece.Material = (Enum.Material :: any)[spec.Material]
			piece.Color = rgb(spec.Color)
			piece.Transparency = spec.Transparency
			piece.Reflectance = spec.Reflectance
			piece.Anchored = true
			piece.CanCollide = spec.Collide
			piece.CanQuery = spec.Collide
			piece.CanTouch = false
			piece.CastShadow = spec.Transparency < 0.5
			piece.CollisionFidelity = Enum.CollisionFidelity.Box
			piece.RenderFidelity = Enum.RenderFidelity.Automatic
			if spec.Surface and SURFACES[spec.Surface] then
				local surface = Instance.new("SurfaceAppearance")
				for key, value in pairs(SURFACES[spec.Surface]) do
					(surface :: any)[key] = value
				end
				surface.Color = rgb(spec.Color):Lerp(Color3.new(1, 1, 1), 0.35)
				surface.Parent = piece
			end
			if spec.Light then
				local light = Instance.new("PointLight")
				light.Color = rgb(spec.Light.Color)
				light.Brightness = spec.Light.Brightness
				light.Range = spec.Light.Range
				light.Shadows = false
				light.Parent = piece
			end
			if spec.Bubbles then
				local bubbles = Instance.new("ParticleEmitter")
				bubbles.Name = "Bubbles"
				bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 240, 230))
				bubbles.LightEmission = 0.3
				bubbles.Size = NumberSequence.new(0.06, 0.12)
				bubbles.Transparency = NumberSequence.new(0.3, 0.9)
				bubbles.Lifetime = NumberRange.new(2.5, 4)
				bubbles.Speed = NumberRange.new(0.6, 1.1)
				bubbles.SpreadAngle = Vector2.new(6, 6)
				bubbles.Rate = 3
				bubbles.EmissionDirection = Enum.NormalId.Top
				bubbles.Shape = Enum.ParticleEmitterShape.Cylinder
				bubbles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
				bubbles.Parent = piece
			end
			piece.Parent = model
			done += 1
		else
			table.insert(skipped, piece.Name)
		end
	end
end
loaded:Destroy()

-- Orientación: en el dispenser las canillas tienen que quedar delante (-Z) del
-- cuerpo. Si quedaron detrás, todo se importó mirando al revés.
local cooler = folder:FindFirstChild("WaterCooler")
if cooler and cooler:FindFirstChild("TapHot") and cooler:FindFirstChild("Body") then
	local offset = cooler.TapHot.Position - cooler.Body.Position
	print("[NocturnaProps] canilla respecto del cuerpo:", offset)
	if creature and creature:FindFirstChild("Head") then
		-- Si todo llegó al revés y la pieza no trae el giro en su CFrame, el giro
		-- está en la malla misma: ChaseCreature la da vuelta al ubicarla.
		local look = creature.Head.CFrame.LookVector
		creature:SetAttribute("MeshTurn", offset.Z > 0 and look.Z < 0)
		print("[NocturnaProps] Organismo MeshTurn:", creature:GetAttribute("MeshTurn"), look)
	end
	if offset.Z > 0 then
		for _, model in ipairs(folder:GetChildren()) do
			if model:IsA("Model") then
				model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.pi, 0))
			end
		end
		print("[NocturnaProps] estaban al revés: se giraron 180°")
	end
end

print("[NocturnaProps] piezas armadas:", done, "sin ficha:", #skipped, table.concat(skipped, ", "))
