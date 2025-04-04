import copy
import dataclasses
from enum import Enum

from open_dread_rando.logger import LOG
from open_dread_rando.patcher_editor import PatcherEditor
from open_dread_rando.pickups.map_icons import MapIcon


class TeleporterColor(Enum):
    CYAN = 0
    BLUE = 1
    GREEN = 2
    ORANGE = 3
    PINK = 4
    PURPLE = 5
    RED = 6
    YELLOW = 7

    @property
    def map_icon_name(self) -> str:
        return f"UsableTeleport{self.map_icon_initial}"

    @property
    def map_icon_initial(self) -> str:
        if self == TeleporterColor.CYAN:
            return "X"
        elif self == TeleporterColor.BLUE:
            return "U"
        elif self == TeleporterColor.GREEN:
            return "O"
        elif self == TeleporterColor.ORANGE:
            return "Y"
        elif self == TeleporterColor.PINK:
            return "Z"
        elif self == TeleporterColor.PURPLE:
            return "E"
        elif self == TeleporterColor.YELLOW:
            return "I"
        else:
            return "A"


class TransporterType(Enum):
    TRANSPORT = "TRANSPORT"
    TELEPORTAL = "TELEPORTAL"

@dataclasses.dataclass
class TransporterIcon:
    default_icon_id: str
    coords: tuple[int, int]
    prefix: str
    disabled_id: str = ''

    def map_icon(self, icon_id: str, label: str) -> MapIcon:
        return MapIcon(
            icon_id=icon_id,
            coords=self.coords,
            label=self.prefix + label.upper(),
            disabled_id=self.disabled_id
        )

    @classmethod
    def get_icon(cls, usable: dict):
        usable_id = usable["sIconId"]
        for trans_type in TRANSPORT_TYPES.values():
            if trans_type.default_icon_id == usable_id:
                return trans_type
        return None


# Additional assets that are required for teleporters
TELEPORTER_ADDITIONAL_ASSETS = [
    "actors/characters/samus/animations/useteleporter.bcskla",
    "actors/characters/samus/animations/useteleporterend.bcskla",
    "actors/characters/samus/animations/useteleporterinit.bcskla",
    "actors/characters/samus/cameras/useteleporterend.bccam",
    "actors/characters/samus/cameras/useteleporterinit.bccam",
    "actors/characters/samus/fx/imats/teleportfresnel.bsmat",
    "actors/characters/samus/fx/teleport_fresnel.bcmdl",
    "system/fx/generic/chozolettersfast_faster.bcptl",
    "system/fx/generic/chozolettersfast.bcptl",
    "system/fx/generic/chozolettersslow.bcptl",
    "system/fx/generic/glowloop_distortionfadeout.bcptl",
    "system/fx/generic/glowloop_distortionfastreverse.bcptl",
    "system/fx/generic/glowloop_teleport.bcptl",
    "system/fx/generic/glowloop_teleportend.bcptl",
    "system/fx/generic/glowloop_teleportfast_faster.bcptl",
    "system/fx/generic/glowloop_teleportfast.bcptl",
    "system/fx/generic/lettersplatform.bcptl",
    "system/fx/generic/letterstoptp.bcptl",
    "system/fx/generic/padlight_tp.bcptl",
    "system/fx/generic/switchlightsoff_tp.bcptl",
]

TRANSPORT_TYPES = {
    "Elevator": TransporterIcon(
        default_icon_id="UsableElevator",
        coords=(2,4),
        prefix="ELEVATOR TO ",
        disabled_id="DisabledElevator",
    ),
    "Train": TransporterIcon(
        default_icon_id="UsableTrain",
        coords=(1,4),
        prefix="SHUTTLE TO ",
    ),
    "Transport": TransporterIcon(
        default_icon_id="UsableTransport",
        coords=(8,2),
        prefix = "TRANSPORT CAPSULE TO ",
    )
}

def _get_type_and_usable(editor: PatcherEditor, elevator: dict) -> tuple[TransporterType, dict]:
    scenario = editor.get_scenario(elevator["teleporter"]["scenario"])
    sublayer = elevator["teleporter"].get("sublayer", elevator["teleporter"].get("layer", "default"))
    actor = scenario.actors_for_sublayer(sublayer)[elevator["teleporter"]["actor"]]

    try:
        usable = actor.pComponents.USABLE
    except AttributeError:
        raise ValueError(f'Actor {elevator["teleporter"]} is not usable')

    if usable["@type"] in ["CElevatorUsableComponent", "CTrainUsableComponent", "CTrainUsableComponentCutScene",
                           "CTrainWithPortalUsableComponent", "CCapsuleUsableComponent"]:
        return TransporterType.TRANSPORT, usable
    elif usable["@type"] == "CTeleporterUsableComponent":
        return TransporterType.TELEPORTAL, usable
    else:
        raise ValueError(f"Elevator {elevator['teleporter']['scenario']}/{elevator['teleporter']['actor']} "
                         "is not an elevator, shuttle, capsule or teleporter!\n"
                         f"USABLE type: {usable['@type']}")

def _patch_actor(usable: dict, elevator: dict):
    usable.sScenarioName = elevator["destination"]["scenario"]
    usable.sTargetSpawnPoint = elevator["destination"]["actor"]

def _patch_minimap_arrows(editor: PatcherEditor, elevator: dict):
    map = editor.get_scenario_map(elevator["teleporter"]["scenario"])
    sign = map.get_category("mapTransportSigns")[ elevator["teleporter"]["actor"] ]
    sign["sDestAreaId"] = elevator["destination"]["scenario"]

def _patch_map_icon(editor: PatcherEditor, elevator: dict):
    # get transporter type from mapUsables entry
    conn_name: str = elevator["connection_name"]
    icon_id = f'RDV_TRANSPORT_{conn_name.replace(" ", "")}' # ex: "RDV_TRANSPORT_Artaria-ThermalDevice"

    bmmap = editor.get_scenario_map(elevator["teleporter"]["scenario"])
    usable = bmmap.get_category("mapUsables")[ elevator["teleporter"]["actor"] ]
    ti = TransporterIcon.get_icon(usable)
    if ti is None:
        raise ValueError(f'Usable icon_id {usable["sIconId"]} invalid!')

    # add BMMDEF
    editor.map_icon_editor.add_icon(ti.map_icon(icon_id, elevator["connection_name"]))

    # update usable
    usable["sIconId"] = icon_id

def patch_elevators(editor: PatcherEditor, elevators_config: list[dict]):
    for elevator in elevators_config:
        LOG.debug("Writing elevator from: %s", str(elevator["teleporter"]))
        transporter_type, usable = _get_type_and_usable(editor, elevator)

        if transporter_type == TransporterType.TRANSPORT:
            _patch_actor(usable, elevator)
            _patch_minimap_arrows(editor, elevator)
            _patch_map_icon(editor, elevator)
        else:
            # TODO implement teleporter rando
            _patch_actor(usable, elevator)


def add_teleporter(editor: PatcherEditor, scenario_name: str, name: str, location: tuple[float, float, float],
                   collision_camera_name: str, destination_scenario_name: str, destination_spawn_point: str,
                   color: TeleporterColor):
    # Create teleporter
    new_teleporter = copy.deepcopy(editor.resolve_actor_reference({
        "scenario": "s020_magma",
        "actor": "LE_Teleport_FromCave",
    }))

    new_teleporter.sName = name
    new_teleporter.vPos = location
    new_teleporter.pComponents.USABLE.eTeleporterColorSphere = color.value
    new_teleporter.pComponents.USABLE.sScenarioName = destination_scenario_name
    new_teleporter.pComponents.USABLE.sTargetSpawnPoint = destination_spawn_point

    # Create platform
    new_platform_name = f"{name}_Platform"
    new_platform = copy.deepcopy(editor.resolve_actor_reference({
        "scenario": "s020_magma",
        "actor": "LE_Platform_Teleport_FromCave",
    }))

    new_platform.sName = new_platform_name
    new_platform.vPos = location
    new_platform.pComponents.SMARTOBJECT.sUsableEntity = name

    # Add new actors to scenario
    scenario = editor.get_scenario(scenario_name)
    scenario.actors_for_sublayer("default")[name] = new_teleporter
    scenario.add_actor_to_actor_groups(f"eg_{collision_camera_name}", name)
    scenario.actors_for_sublayer("default")[new_platform_name] = new_platform
    scenario.add_actor_to_actor_groups(f"eg_{collision_camera_name}", new_platform_name)

    # Add map icon
    magma_map = editor.get_scenario_map("s020_magma")
    scenario_map = editor.get_scenario_map(scenario_name)
    new_map_icon = copy.deepcopy(magma_map.get_category("mapUsables")["LE_Teleport_FromCave"])
    new_map_icon.vPos = new_teleporter.vPos[:2]
    new_map_icon.oBox.Min = [c + offset for c, offset in zip(new_teleporter.vPos, (-150.0, 0.0))]
    new_map_icon.oBox.Max = [c + offset for c, offset in zip(new_teleporter.vPos, (150.0, 500.0))]
    new_map_icon.sIconId = color.map_icon_name
    scenario_map.get_category("mapUsables")[name] = new_map_icon

    # Ensure scenario package has necessary assets for teleporters
    for charclass in [
        "actors/props/teleporter",
        "actors/props/weightactivatedplatform_teleport",
    ]:
        for asset_id in editor.get_asset_names_in_folder(charclass):
            editor.ensure_present_in_scenario(scenario_name, asset_id)

    for asset_id in TELEPORTER_ADDITIONAL_ASSETS:
        editor.ensure_present_in_scenario(scenario_name, asset_id)