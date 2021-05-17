# Copyright 2016 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to save and load Zurich Instruments device settings using the
zhinst.utils utility functions save_settings() and load_settings().

Connect to a Zurich Instruments instrument, save the instrument's settings to
file, toggle the signal output enable and reload the settings file.

This example demonstrates the use of the zhinst utility functions
save_settings() and load_settings(). These functions will block until
saving/loading has finished (i.e., they are synchronous functions). Since
this is the desired behaviour in most cases, these utility functions are the
recommended way to save and load settings.

If an asynchronous interface for saving and loading settings is required,
please refer to the `example_save_device_settings_expert'. Which
demonstrates how to directly use the ziDeviceSettings module.

Requirements:
    * LabOne Version >= 20.02
    * Instruments:
        1 x Instrument with demodulators
    * signal output 1 connected to signal input 1 with a BNC cable.

Usage:
    example_save_device_settings_simple.py [options] <device_id>
    example_save_device_settings_simple.py -h | --help

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

See the "LabOne Programming Manual" for further help, available:
    - On Windows via the Start-Menu:
    Programs -> Zurich Instruments -> Documentation
    - On Linux in the LabOne .tar.gz archive in the "Documentation"
    sub-folder.
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
    # - the device's discovery properties.
    (daq, device, _) = zhinst.utils.create_api_session(device_id, apilevel_example)
    zhinst.utils.api_server_version_check(daq)

    timestr = time.strftime("%Y%m%d_%H%M%S")
    filename = (
        timestr + "_example_save_device_settings_simple.xml"
    )  # Change this to the filename you want to save.
    if setting:
        print("setting:")
        print(setting)
        filename = setting + os.sep + filename

    toggle_device_setting(daq, device)

    # Save the instrument's current settings.
    print("Saving settings...")
    zhinst.utils.save_settings(daq, device, filename)
    print("Done.")

    # Check we actually saved the file
    assert os.path.isfile(filename), "Failed to save settings file '%s'" % filename
    print(f"Saved file '{filename}'.")

    toggle_device_setting(daq, device)

    # Load settings.
    print("Loading settings...")
    zhinst.utils.load_settings(daq, device, filename)
    print("Done.")

    return filename


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
