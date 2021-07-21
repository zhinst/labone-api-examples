# Copyright 2016 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to save and load Zurich Instruments device settings
asynchronously using the ziDeviceSettings class.

Note: This example is intended for experienced users who require a non-blocking
(asynchronous) interface for loading and saving settings. In general, the
utility functions save_settings() and load_settings() are more appropriate; see
`example_save_device_settings_simple`.

Requirements:
    * LabOne Version >= 20.02
    * Instruments:
        1 x Instrument with demodulators
    * signal output 1 connected to signal input 1 with a BNC cable.

Usage:
    example_save_device_settings_expert.py [options] <device_id>
    example_save_device_settings_expert.py -h | --help

Arguments:
    <device_id>  The ID of the device [device_type: .*LI|.*IA|.*IS]

Options:
    -h --help          Show this screen.
    -s --setting PATH  Specify the path where to save the settings file. [default: ]

Returns:
    filename (str)  the name (with path) of the XML file where the settings were saved.

Raises:
    Exception     If the specified devices do not match the requirements.
    RuntimeError  If the devices is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""

import time
import os
import zhinst.utils


def run_example(device_id: str, setting: str = ""):
    """run the example."""

    apilevel_example = 6  # The API level supported by this example.
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    (daq, device, _) = zhinst.utils.create_api_session(device_id, apilevel_example)
    zhinst.utils.api_server_version_check(daq)

    timestr = time.strftime("%Y%m%d_%H%M%S")
    filename_noext = (
        timestr + "_example_save_device_settings_expert"
    )  # Change this to the filename you want to save.

    device_settings = daq.deviceSettings()
    device_settings.set("device", device)
    device_settings.set("filename", filename_noext)
    if setting:
        device_settings.set("path", setting)
    # Set the path to '.' save to the current directory.
    # device_settings.set('path', '.')
    # NOTE: in this case, this example will have to be executed from a folder
    # where you have write access.

    toggle_device_setting(daq, device)

    # Save the instrument's current settings.
    print("Saving settings...")
    device_settings.set("command", "save")
    device_settings.execute()
    while not device_settings.finished():
        time.sleep(0.2)
    print("Done.")

    data = device_settings.get("path")
    path = data["path"][0]
    filename_full_path = os.path.join(path, filename_noext) + ".xml"
    assert os.path.isfile(filename_full_path), (
        "Failed to save settings file '%s'" % filename_full_path
    )
    print(f"Saved file '{filename_full_path}'.")

    toggle_device_setting(daq, device)

    # Load the settings.
    print("Loading settings...")
    device_settings.set("command", "save")
    device_settings.execute()
    while not device_settings.finished():
        time.sleep(0.2)
    print("Done.")

    return filename_full_path


def toggle_device_setting(daq, device):
    """
    Toggle a setting on the device: If it's enabled, disable the setting, and
    vice versa.
    """
    path = "/%s/sigouts/0/on" % device
    is_enabled = daq.getInt(path)
    print(f"Toggling setting '{path}'.")
    daq.setInt(path, not is_enabled)
    daq.sync()


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
