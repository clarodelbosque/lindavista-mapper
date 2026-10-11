#!/usr/bin/env python3
"""Writes a small ASCII FBX 7.4 stage for testing Linda Vista Mapper.

The scene has a floor and a pillar (stage), two screens with standard UVs (0,0 at the
bottom-left), a guide frame and two cameras. With --meters the same scene is written in
meters with UnitScaleFactor=100, which must load identically once converted to centimeters.
"""
import sys

UNIT = 1.0


def quad(p0, p1, p2, p3):
    """Counter-clockwise quad as seen from its front side: bottom-left, bottom-right, top-right, top-left."""
    return [p0, p1, p2, p3]


def normal_of(q):
    ax, ay, az = (q[1][i] - q[0][i] for i in range(3))
    bx, by, bz = (q[3][i] - q[0][i] for i in range(3))
    n = (ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx)
    length = sum(c * c for c in n) ** 0.5
    return tuple(c / length for c in n)


def box(cx, cy, cz, sx, sy, sz):
    x0, x1 = cx - sx / 2, cx + sx / 2
    y0, y1 = cy - sy / 2, cy + sy / 2
    z0, z1 = cz - sz / 2, cz + sz / 2
    return [
        quad((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)),  # +Z
        quad((x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)),  # -Z
        quad((x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)),  # +X
        quad((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)),  # -X
        quad((x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)),  # +Y
        quad((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)),  # -Y
    ]


def fmt(values):
    return ",".join(f"{v:.6g}" for v in values)


class Writer:
    def __init__(self):
        self.objects = []
        self.connections = []
        self.next_id = 1000

    def new_id(self):
        self.next_id += 1
        return self.next_id

    def material(self, name, diffuse, emissive=(0, 0, 0)):
        mid = self.new_id()
        self.objects.append(f"""	Material: {mid}, "Material::{name}", "" {{
		Version: 102
		ShadingModel: "phong"
		MultiLayer: 0
		Properties70:  {{
			P: "DiffuseColor", "Color", "", "A",{fmt(diffuse)}
			P: "DiffuseFactor", "Number", "", "A",1
			P: "EmissiveColor", "Color", "", "A",{fmt(emissive)}
			P: "EmissiveFactor", "Number", "", "A",1
			P: "AmbientColor", "Color", "", "A",0,0,0
			P: "SpecularColor", "Color", "", "A",0,0,0
		}}
	}}""")
        return mid

    def mesh(self, name, quads, uvs=None, material=None):
        model_id, geom_id = self.new_id(), self.new_id()
        verts, indices, normals = [], [], []
        for q in quads:
            base = len(verts) // 3
            for p in q:
                verts.extend(c * UNIT for c in p)
            indices.extend([base, base + 1, base + 2, -(base + 3) - 1])
            normals.extend(list(normal_of(q)) * 4)
        uv_block = ""
        layer_uv = ""
        if uvs:
            uv_values = [c for q in uvs for uv in q for c in uv]
            uv_block = f"""
		LayerElementUV: 0 {{
			Version: 101
			Name: "UVMap"
			MappingInformationType: "ByPolygonVertex"
			ReferenceInformationType: "IndexToDirect"
			UV: *{len(uv_values)} {{
				a: {fmt(uv_values)}
			}}
			UVIndex: *{len(uv_values) // 2} {{
				a: {fmt(range(len(uv_values) // 2))}
			}}
		}}"""
            layer_uv = """
			LayerElement:  {
				Type: "LayerElementUV"
				TypedIndex: 0
			}"""
        self.objects.append(f"""	Geometry: {geom_id}, "Geometry::{name}", "Mesh" {{
		Vertices: *{len(verts)} {{
			a: {fmt(verts)}
		}}
		PolygonVertexIndex: *{len(indices)} {{
			a: {",".join(str(i) for i in indices)}
		}}
		GeometryVersion: 124
		LayerElementNormal: 0 {{
			Version: 101
			Name: ""
			MappingInformationType: "ByPolygonVertex"
			ReferenceInformationType: "Direct"
			Normals: *{len(normals)} {{
				a: {fmt(normals)}
			}}
		}}{uv_block}
		LayerElementMaterial: 0 {{
			Version: 101
			Name: ""
			MappingInformationType: "AllSame"
			ReferenceInformationType: "IndexToDirect"
			Materials: *1 {{
				a: 0
			}}
		}}
		Layer: 0 {{
			Version: 100
			LayerElement:  {{
				Type: "LayerElementNormal"
				TypedIndex: 0
			}}{layer_uv}
			LayerElement:  {{
				Type: "LayerElementMaterial"
				TypedIndex: 0
			}}
		}}
	}}
	Model: {model_id}, "Model::{name}", "Mesh" {{
		Version: 232
		Properties70:  {{
			P: "Lcl Translation", "Lcl Translation", "", "A",0,0,0
		}}
		Shading: T
		Culling: "CullingOff"
	}}""")
        self.connections += [(model_id, 0), (geom_id, model_id)]
        if material:
            self.connections.append((material, model_id))

    def camera(self, name, position, rotation, fov):
        attr_id, model_id = self.new_id(), self.new_id()
        self.objects.append(f"""	NodeAttribute: {attr_id}, "NodeAttribute::{name}", "Camera" {{
		Properties70:  {{
			P: "ApertureMode", "enum", "", "",2
			P: "FieldOfView", "FieldOfView", "", "A",{fov}
			P: "NearPlane", "double", "Number", "",{10 * UNIT}
			P: "FarPlane", "double", "Number", "",{100000 * UNIT}
		}}
		TypeFlags: "Camera"
		GeometryVersion: 124
		Position: 0,0,0
		Up: 0,1,0
		LookAt: 0,0,0
	}}
	Model: {model_id}, "Model::{name}", "Camera" {{
		Version: 232
		Properties70:  {{
			P: "Lcl Translation", "Lcl Translation", "", "A",{fmt(c * UNIT for c in position)}
			P: "Lcl Rotation", "Lcl Rotation", "", "A",{fmt(rotation)}
		}}
	}}""")
        self.connections += [(model_id, 0), (attr_id, model_id)]

    def write(self, path, unit_scale):
        header = f"""; FBX 7.4.0 project file
FBXHeaderExtension:  {{
	FBXHeaderVersion: 1003
	FBXVersion: 7400
	Creator: "Linda Vista Mapper test scene generator"
}}
GlobalSettings:  {{
	Version: 1000
	Properties70:  {{
		P: "UpAxis", "int", "Integer", "",1
		P: "UpAxisSign", "int", "Integer", "",1
		P: "FrontAxis", "int", "Integer", "",2
		P: "FrontAxisSign", "int", "Integer", "",1
		P: "CoordAxis", "int", "Integer", "",0
		P: "CoordAxisSign", "int", "Integer", "",1
		P: "UnitScaleFactor", "double", "Number", "",{unit_scale}
		P: "OriginalUnitScaleFactor", "double", "Number", "",{unit_scale}
	}}
}}
"""
        body = "Objects:  {\n" + "\n".join(self.objects) + "\n}\n"
        conns = "Connections:  {\n" + "\n".join(f'	C: "OO",{a},{b}' for a, b in self.connections) + "\n}\n"
        with open(path, "w") as f:
            f.write(header + body + conns)


def build(path, meters):
    global UNIT
    UNIT = 0.01 if meters else 1.0
    w = Writer()
    gray = w.material("stage_gray", (0.45, 0.47, 0.52))
    white = w.material("screen_white", (1, 1, 1))
    yellow = w.material("guide_yellow", (0.1, 0.1, 0.0), emissive=(0.9, 0.8, 0.1))
    std_uv = [[(0, 0), (1, 0), (1, 1), (0, 1)]]

    w.mesh("floor", box(0, -10, 0, 800, 20, 600), material=gray)
    w.mesh("pillar", box(260, 125, -120, 40, 250, 40), material=gray)
    w.mesh("screen_center", [quad((-160, 30, -200), (160, 30, -200), (160, 210, -200), (-160, 210, -200))], std_uv, white)
    w.mesh("screen_left", [quad((-380, 30, -40), (-220, 30, -180), (-220, 150, -180), (-380, 150, -40))], std_uv, white)
    frame = [
        quad((-170, 20, -199), (170, 20, -199), (170, 28, -199), (-170, 28, -199)),
        quad((-170, 212, -199), (170, 212, -199), (170, 220, -199), (-170, 220, -199)),
    ]
    w.mesh("guide_frame", frame, material=yellow)
    w.camera("Front", (0, 120, 600), (0, 90, 0), 40)
    w.camera("Top", (0, 900, 0), (0, 0, -90), 60)
    w.write(path, 100 if meters else 1)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit("usage: make_test_scene.py OUT.fbx [--meters]")
    build(args[0], "--meters" in sys.argv)
