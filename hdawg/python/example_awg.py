# Copyright 2018 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to connect to a Zurich Instruments HDAWG and upload and run an
AWG program.

Requirements:
    * LabOne Version >= 21.02
    * Instruments:
        1 x HDAWG Instrument

Hardware configuration:
    Connect signal outputs 1 and 2 to signal inputs 1 and 2 with BNC cables.

Usage:
    example_awg_sourcefile.py [options] <device_id>
    example_awg_sourcefile.py -h | --help

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
import textwrap
import numpy as np
import zhinst.utils


def run_example(device_id):
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
    # Configure the HDAWG to use one sequencer for each pair of output channels
    daq.setInt(f"/{device}/system/awg/channelgrouping", 0)

    # Some basic device configuration to output the generated wave.
    out_channel = 0
    awg_channel = 0
    amplitude = 1.0

    exp_setting = [
        ["/%s/sigouts/%d/on" % (device, out_channel), 1],
        ["/%s/sigouts/%d/range" % (device, out_channel), 1],
        ["/%s/awgs/0/outputs/%d/amplitude" % (device, awg_channel), amplitude],
        ["/%s/awgs/0/outputs/0/modulation/mode" % device, 0],
        ["/%s/awgs/0/time" % device, 0],
        ["/%s/awgs/0/userregs/0" % device, 0],
    ]
    daq.set(exp_setting)
    # Ensure that all settings have taken effect on the device before continuing.
    daq.sync()

    # Number of points in AWG waveform
    AWG_N = 2000

    # Define an AWG program as a string stored in the variable awg_program, equivalent to what would
    # be entered in the Sequence Editor window in the graphical UI.
    # This example demonstrates four methods of definig waveforms via the API
    # - (wave w0) loaded directly from programmatically generated CSV file wave0.csv.
    #             Waveform shape: Blackman window with negative amplitude.
    # - (wave w1) using the waveform generation functionalities available in the AWG Sequencer
    #             language.
    #             Waveform shape: Gaussian function with positive amplitude.
    # - (wave w2) using the vect() function and programmatic string replacement.
    #             Waveform shape: Single period of a sine wave.
    # - (wave w3) directly writing an array of numbers to the AWG waveform memory.
    #             Waveform shape: Sinc function. In the sequencer language, the waveform is
    #             initially defined as an array of zeros. This placeholder array is later
    #             overwritten with the sinc function.

    awg_program = textwrap.dedent(
        """\
        const AWG_N = _c1_;
        wave w0 = "wave0";
        wave w1 = gauss(AWG_N, AWG_N/2, AWG_N/20);
        wave w2 = vect(_w2_);
        wave w3 = zeros(AWG_N);
        while(getUserReg(0) == 0);
        setTrigger(1);
        setTrigger(0);
        playWave(w0);
        playWave(w1);
        playWave(w2);
        playWave(w3);
        """
    )

    # Define an array of values that are used to write values for wave w0 to a CSV file in the
    # module's data directory
    waveform_0 = -1.0 * np.blackman(AWG_N)

    # Define an array of values that are used to generate wave w2
    waveform_2 = np.sin(np.linspace(0, 2 * np.pi, 96))

    # Fill the waveform values into the predefined program by inserting the array
    # as comma-separated floating-point numbers into awg_program.
    # Warning: Defining waveforms with the vect function can increase the code size
    #          considerably and should be used for short waveforms only.
    awg_program = awg_program.replace("_w2_", ",".join([str(x) for x in waveform_2]))

    # Fill in the integer constant AWG_N
    awg_program = awg_program.replace("_c1_", str(AWG_N))

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
    # Save waveform data to CSV
    csv_file = os.path.join(wave_dir, "wave0.csv")
    np.savetxt(csv_file, waveform_0)

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

    # Replace the waveform w3 with a new one.
    waveform_3 = np.sinc(np.linspace(-6 * np.pi, 6 * np.pi, AWG_N))
    # Let N be the total number of waveforms and M>0 be the number of waveforms defined from CSV
    # files. Then the index of the waveform to be replaced is defined as following:
    # - 0,...,M-1 for all waveforms defined from CSV file alphabetically ordered by filename,
    # - M,...,N-1 in the order that the waveforms are defined in the sequencer program.
    # For the case of M=0, the index is defined as:
    # - 0,...,N-1 in the order that the waveforms are defined in the sequencer program.
    # Of course, for the trivial case of 1 waveform, use index=0 to replace it.
    # The list of waves given in the Waveform sub-tab of the AWG Sequencer tab can be used to help
    # verify the index of the waveform to be replaced.
    # Here we replace waveform w3, the 4th waveform defined in the sequencer program. Using 0-based
    # indexing the index of the waveform we want to replace (w3, a vector of zeros) is 3:
    index = 3
    waveform_native = zhinst.utils.convert_awg_waveform(waveform_3)
    path = f"/{device:s}/awgs/0/waveform/waves/{index:d}"
    daq.setVector(path, waveform_native)

    print(
        f"Enabling the AWG: Set /{device}/awgs/0/userregs/0 to 1 to trigger waveform playback."
    )
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
