# Copyright 2020 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to connect to a Zurich Instruments HDAWG and upload and run an
AWG program using the command table.

Requirements:
    * LabOne Version >= 21.02
    * Instruments:
        1 x HDAWG Instrument

Hardware configuration:
    Connect signal outputs 1 and 2 to signal inputs 1 and 2 with BNC cables.

Usage:
    example_awg_commandtable.py [options] <device_id>
    example_awg_commandtable.py -h | --help

Arguments:
    <device_id>  The ID of the device to run the example with. [device_type: HDAWG]

Options:
    -h --help                 Show this screen.

Raises:
    Exception     If the specified device does not match the requirements.
    RuntimeError  If the device is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""

import os
import time
import json
import textwrap
import numpy as np
import zhinst.utils


def validate_json(json_str):
    """Validate if string is a valid JSON"""
    try:
        json.loads(json_str)
    except ValueError:
        return False

    return True


def run_example(device_id: str):
    """run the example."""

    # Settings
    apilevel_example = 6  # The API level supported by this example.
    err_msg = "This example can only be ran on an HDAWG."
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    # - the device's discovery properties.
    (daq, device, _) = zhinst.utils.create_api_session(
        device_id, apilevel_example, required_devtype="HDAWG", required_err_msg=err_msg
    )
    zhinst.utils.api_server_version_check(daq)

    # Create a base configuration: Disable all available outputs, awgs, demods, scopes,...
    zhinst.utils.disable_everything(daq, device)

    # 'system/awg/channelgrouping' : Configure how many independent sequencers
    #   should run on the AWG and how the outputs are grouped by sequencer.
    #   0 : 4x2 with HDAWG8; 2x2 with HDAWG4.
    #   1 : 2x4 with HDAWG8; 1x4 with HDAWG4.
    #   2 : 1x8 with HDAWG8.
    # Configure the HDAWG to use one sequencer with the same waveform on all output channels.
    daq.setInt(f"/{device}/system/awg/channelgrouping", 0)

    # Some basic device configuration to output the generated wave on Wave outputs 1 and 2.
    amplitude = 1.0

    exp_setting = [
        [f"/{device}/sigouts/0/on", 1],
        [f"/{device}/sigouts/1/on", 1],
        [f"/{device}/sigouts/0/range", 1],
        [f"/{device}/sigouts/1/range", 1],
        [f"/{device}/awgs/0/outputs/0/amplitude", amplitude],
        [f"/{device}/awgs/0/outputs/1/amplitude", amplitude],
        [f"/{device}/awgs/0/outputs/0/modulation/mode", 0],
        [f"/{device}/awgs/0/time", 0],
        [f"/{device}/awgs/*/enable", 0],
        [f"/{device}/awgs/0/userregs/0", 0],
    ]
    daq.set(exp_setting)
    # Ensure that all settings have taken effect on the device before continuing.
    daq.sync()

    # Define an AWG program as a string stored in the variable awg_program, equivalent to what would
    # be entered in the Sequence Editor window in the graphical UI. Different to a self-contained
    # program, this example refers to a command table by the instruction "executeTableEntry", and to
    # a placeholder waveform p by the instruction "placeholder". Both the command table and the
    # waveform data for the waveform p need to be uploaded separately before this sequence program
    # can be run.

    awg_program = textwrap.dedent(
        """\
        // Define placeholder with 1024 samples:
        wave p = placeholder(1024);

        // Assign placeholder to waveform index 10
        assignWaveIndex(p, p, 10);

        while(true) {
          executeTableEntry(0);
        }
        """
    )

    # JSON string specifying the command table to be uploadedCommand Table JSON
    json_str = textwrap.dedent(
        """
        {
          "$schema": "http://docs.zhinst.com/hdawg/commandtable/v2/schema",
          "header": {
            "version": "0.2",
            "partial": false
          },
          "table": [
            {
              "index": 0,
              "waveform": {
                "index": 10
              },
              "amplitude0": {
                "value": 1.0
              },
              "amplitude1": {
                "value": 1.0
              }
            }
          ]
        }
        """
    )

    # Ensure command table is valid (valid JSON and compliant with schema)
    assert validate_json(json_str)

    # Create an instance of the AWG Module
    awgModule = daq.awgModule()
    awgModule.set("device", device)
    awgModule.execute()

    # Get the modules data directory
    data_dir = awgModule.getString("directory")
    # All CSV files within the waves directory are automatically recognized by the AWG module
    wave_dir = os.path.join(data_dir, "awg", "waves")
    if not os.path.isdir(wave_dir):
        # The data directory is created by the AWG module and should always exist. If this exception
        # is raised, something might be wrong with the file system.
        raise Exception(
            f"AWG module wave directory {wave_dir} does not exist or is not a directory"
        )

    # Transfer the AWG sequence program. Compilation starts automatically.
    awgModule.set("compiler/sourcestring", awg_program)
    # Note: when using an AWG program from a source file (and only then), the compiler needs to
    # be started explicitly with awgModule.set('compiler/start', 1)
    while awgModule.getInt("compiler/status") == -1:
        time.sleep(0.1)

    if awgModule.getInt("compiler/status") == 1:
        # compilation failed, raise an exception
        raise Exception(awgModule.getString("compiler/statusstring"))

    if awgModule.getInt("compiler/status") == 0:
        print(
            "Compilation successful with no warnings, will upload the program to the instrument."
        )
    if awgModule.getInt("compiler/status") == 2:
        print(
            "Compilation successful with warnings, will upload the program to the instrument."
        )
        print("Compiler warning: ", awgModule.getString("compiler/statusstring"))

    # Wait for the waveform upload to finish
    time.sleep(0.2)
    i = 0
    while (awgModule.getDouble("progress") < 1.0) and (
        awgModule.getInt("elf/status") != 1
    ):
        print(f"{i} progress: {awgModule.getDouble('progress'):.2f}")
        time.sleep(0.2)
        i += 1
    print(f"{i} progress: {awgModule.getDouble('progress'):.2f}")
    if awgModule.getInt("elf/status") == 0:
        print("Upload to the instrument successful.")
    if awgModule.getInt("elf/status") == 1:
        raise Exception("Upload to the instrument failed.")

    # Upload command table
    daq.setVector(f"/{device}/awgs/0/commandtable/data", json_str)

    # Replace the placeholder waveform with a new one with a Gaussian shape
    x_array = np.linspace(0, 1024, 1024)
    x_center = 512
    sigma = 150
    waveform = np.array(
        np.exp(-np.power(x_array - x_center, 2.0) / (2 * np.power(sigma, 2.0))),
        dtype=float,
    )
    waveform_native = zhinst.utils.convert_awg_waveform(waveform, -waveform)

    # Upload waveform data with the index 10 (this is the index assigned with the assignWaveIndex
    # sequencer instruction
    index = 10
    path = f"/{device:s}/awgs/0/waveform/waves/{index:d}"
    daq.setVector(path, waveform_native)

    print("Enabling the AWG.")
    # This is the preferred method of using the AWG: Run in single mode continuous waveform playback
    # is best achieved by using an infinite loop (e.g., while (true)) in the sequencer program.
    daq.setInt(f"/{device}/awgs/0/single", 1)
    daq.setInt(f"/{device}/awgs/0/enable", 1)


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
