# Copyright 2018 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to connect to a Zurich Instruments Arbitrary Waveform Generator
and compile/upload an AWG program to the instrument.
Connect to a Zurich Instruments UHF Lock-in Amplifier, UHFAWG or UHFQA, compile,
upload and run an AWG sequence program.

Requirements:
    * LabOne Version >= 21.02
    * Instruments:
        1 x UHFAWG or UHFLI with UHF-AWG Arbitrary Waveform Generator Option.

Usage:
    example_awg_sourcefile.py [options] <device_id>
    example_awg_sourcefile.py -h | --help

Arguments:
    <device_id>  The ID of the device to run the example with. [device_type: UHF(AWG)]

Options:
    -h --help              Show this screen.
    -s --server_host IP    Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT  Port number of the data server [default: 8004]
    --awg_sourcefile       Specify an AWG sequencer file to compile and upload.
                           This file must exist in the AWG source sub-folder of your
                           LabOne data directory (this location is provided by the
                           directory parameter). The source folder must not be included;
                           specify the filename only with extension. [default: ]

Raises:
    Exception     If the specified device does not match the requirements.
    RuntimeError  If the device is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""

import time
import textwrap
import os
import zhinst.utils

# This is only used if this example is ran without the awg_sourcefile
# parameter: To ensure that we have a .seqc source file to use in this example,
# we write this to disk and then compile this file.
SOURCE = textwrap.dedent(
    """// Define an integer constant
    const N = 4096;
    // Create two Gaussian pulses with length N points,
    // amplitude +1.0 (-1.0), center at N/2, and a width of N/8
    wave gauss_pos = 1.0*gauss(N, N/2, N/8);
    wave gauss_neg = -1.0*gauss(N, N/2, N/8);
    // Continuous playback.
    while (true) {
      // Play pulse on AWG channel 1
      playWave(gauss_pos);
      // Wait until waveform playback has ended
      waitWave();
      // Play pulses simultaneously on both AWG channels
      playWave(gauss_pos, gauss_neg);
    }"""
)


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = 8004,
    awg_sourcefile: str = "",
):
    """run the example."""

    # Settings
    apilevel_example = 6  # The API level supported by this example.
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    # - the device's discovery properties.
    (daq, device, _) = zhinst.utils.create_api_session(
        device_id, apilevel_example, server_host=server_host, server_port=server_port
    )
    zhinst.utils.api_server_version_check(daq)

    # Create a base configuration: Disable all available outputs, awgs, demods, scopes,...
    zhinst.utils.disable_everything(daq, device)

    # Create an instance of the AWG Module
    awgModule = daq.awgModule()
    awgModule.set("device", device)
    awgModule.execute()

    # Get the LabOne user data directory (this is read-only).
    data_dir = awgModule.getString("directory")
    # The AWG Tab in the LabOne UI also uses this directory for AWG seqc files.
    src_dir = os.path.join(data_dir, "awg", "src")
    if not os.path.isdir(src_dir):
        # The data directory is created by the AWG module and should always exist. If this exception
        # is raised, something might be wrong with the file system.
        raise Exception(
            f"AWG module wave directory {src_dir} does not exist or is not a directory"
        )

    # Note, the AWG source file must be located in the AWG source directory of the user's LabOne
    # data directory.
    if not awg_sourcefile:
        # Write an AWG source file to disk that we can compile in this example.
        awg_sourcefile = "ziPython_example_awg_sourcefile.seqc"
        with open(os.path.join(src_dir, awg_sourcefile), "w") as f:
            f.write(SOURCE)
    else:
        if not os.path.exists(os.path.join(src_dir, awg_sourcefile)):
            raise Exception(
                f"The file {awg_sourcefile} does not exist, this must be specified via an absolute \
                    or relative path."
            )

    print("Will compile and load", awg_sourcefile, "from", src_dir)

    # Transfer the AWG sequence program. Compilation starts automatically.
    awgModule.set("compiler/sourcefile", awg_sourcefile)
    # Note: when using an AWG program from a source file (and only then), the compiler needs to
    # be started explicitly:
    awgModule.set("compiler/start", 1)
    timeout = 20
    t0 = time.time()
    while awgModule.getInt("compiler/status") == -1:
        time.sleep(0.1)
        if time.time() - t0 > timeout:
            Exception("Timeout")

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
        time.sleep(0.5)
        i += 1
    print(f"{i} progress: {awgModule.getDouble('progress'):.2f}")
    if awgModule.getInt("elf/status") == 0:
        print("Upload to the instrument successful.")
    if awgModule.getInt("elf/status") == 1:
        raise Exception("Upload to the instrument failed.")

    print("Success. Enabling the AWG.")
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
