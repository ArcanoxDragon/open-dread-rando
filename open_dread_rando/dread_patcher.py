import json
import logging
from pathlib import Path

import jsonschema
from mercury_engine_data_structures.pkg_editor import PkgEditor

LOG = logging.getLogger("dread_patcher")


def _read_schema():
    with Path(__file__).parent.joinpath("schema.json").open() as f:
        return json.load(f)


def patch(input_path: Path, output_path: Path, configuration: dict):
    LOG.info("Will patch files at %s", input_path)

    jsonschema.validate(instance=configuration, schema=_read_schema())

    out_romfs = output_path.joinpath("romfs")
    editor = PkgEditor(input_path)

    original_init_out = out_romfs.joinpath("system/scripts/original_init.lc")
    if not original_init_out.is_file():
        original_lc = editor.get_raw_asset("system/scripts/init.lc")
        original_init_out.parent.mkdir(parents=True, exist_ok=True)
        original_init_out.write_bytes(original_lc)
        # editor.add_new_asset(
        #     "system/scripts/original_init.lc",
        #     original_lc,
        #     editor.find_pkgs("system/scripts/init.lc")
        # )

    # inventory = {
    #     "ITEM_MAX_LIFE": 99,
    #     "ITEM_MAX_SPECIAL_ENERGY": 1000,
    #     "ITEM_WEAPON_MISSILE_MAX": 15,
    #     "ITEM_WEAPON_POWER_BOMB_MAX": 0,
    #     "ITEM_METROID_COUNT": 0,
    #     "ITEM_METROID_TOTAL_COUNT": 40,
    #     "ITEM_FLOOR_SLIDE": 1,
    # }

    custom_init = """
    
--msemenu_ingame.sProfile = nil
   
Game.LogWarn(0, "Will load original init.lc")
Game.ImportLibrary("system/scripts/original_init.lua")
Game.LogWarn(0, "Init = " .. tostring(Init))

local count = 0
for k, v in pairs(Init) do
    Game.LogWarn(0, "Init " .. tostring(k) .. " = " .. tostring(v))
    count = count + 1 
end
Game.LogWarn(0, "Init field count: " .. tostring(count))

Init.tNewGameInventory = {{ 
{new_game_inventory}
}}

function Game.StartPrologue(arg1, arg2, arg3, arg4, arg4)
    Game.LogWarn(0, string.format("Will start Game - %s / %s / %s / %s", tostring(arg1), tostring(arg2), tostring(arg3), tostring(arg4)))
    Game.LoadScenario("c10_samus", "{starting_level}", "{starting_actor}", "", 1)
end

Game.LogWarn(0, "Finished modded msemenu_profile.lc")

""".format(
        new_game_inventory="\n".join(
            "{} = {},".format(key, value)
            for key, value in configuration["starting_items"].items()
        ),
        starting_level=configuration["starting_location"]["level"],
        starting_actor=configuration["starting_location"]["actor"],
    )

    print(custom_init)
    #
    # profile_path = output_path.joinpath("romfs", "gui", "scripts", "msemenu_profile.lc")
    # profile_path.parent.mkdir(parents=True, exist_ok=True)
    # profile_path.write_text(custom_init, "ascii")

    editor.replace_asset("system/scripts/init.lc", custom_init.encode("ascii"))
    editor.save_modified_pkgs(out_romfs)
