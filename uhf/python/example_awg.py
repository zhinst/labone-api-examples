# Copyright 2016 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to connect to a Zurich Instruments UHF Lock-in Amplifier and
upload and run an AWG program.

Requirements:
    * LabOne Version >= 21.02
    * Instruments:
        1 x UHFAWG or UHFLI with UHF-AWG Arbitrary Waveform Generator Option.
    * Signal output 1 connected to signal input 1 with a BNC cable.

Usage:
    example_awg.py [options] <device_id>
    example_awg.py -h | --help

Arguments:
    <device_id>  The ID of the device to run the example with. [device_type: UHF(AWG)]

Options:
    -h --help              Show this screen.
    -s --server_host IP    Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT  Port number of the data server [default: 8004]
    --no-plot              Hide plot of the recorded data.

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
import matplotlib.pyplot as plt


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = 8004,
    plot: bool = True,
):
    """run the example."""

    # Settings
    apilevel_example = 6  # The API level supported by this example.
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    # - the device's discovery properties.
    (daq, device, props) = zhinst.utils.create_api_session(
        device_id, apilevel_example, server_host=server_host, server_port=server_port
    )
    zhinst.utils.api_server_version_check(daq)

    # Create a base configuration: Disable all available outputs, awgs, demods, scopes,...
    zhinst.utils.disable_everything(daq, device)

    # Now configure the instrument for this experiment. The following channels
    # and indices work on all device configurations. The values below may be
    # changed if the instrument has multiple input/output channels and/or either
    # the Multifrequency or Multidemodulator options installed.
    out_channel = 0
    out_mixer_channel = zhinst.utils.default_output_mixer_channel(props, out_channel)
    in_channel = 0
    osc_index = 0
    awg_channel = 0
    frequency = 1e6
    amplitude = 1.0

    exp_setting = [
        ["/%s/sigins/%d/imp50" % (device, in_channel), 1],
        ["/%s/sigins/%d/ac" % (device, in_channel), 0],
        ["/%s/sigins/%d/diff" % (device, in_channel), 0],
        ["/%s/sigins/%d/range" % (device, in_channel), 1],
        ["/%s/oscs/%d/freq" % (device, osc_index), frequency],
        ["/%s/sigouts/%d/on" % (device, out_channel), 1],
        ["/%s/sigouts/%d/range" % (device, out_channel), 1],
        ["/%s/sigouts/%d/enables/%d" % (device, out_channel, out_mixer_channel), 1],
        ["/%s/sigouts/%d/amplitudes/*" % (device, out_channel), 0.0],
        ["/%s/awgs/0/outputs/%d/amplitude" % (device, awg_channel), amplitude],
        ["/%s/awgs/0/outputs/0/mode" % device, 0],
        ["/%s/awgs/0/time" % device, 0],
        ["/%s/awgs/0/userregs/0" % device, 0],
    ]
    daq.set(exp_setting)

    daq.sync()

    # Number of points in AWG waveform
    AWG_N = 2000

    # Define an AWG program as a string stored in the variable awg_program, equivalent to what would
    # be entered in the Sequence Editor window in the graphical UI.
    # This example demonstrates four methods of definig waveforms via the API
    # - (wave w0) loaded directly from programmatically generated CSV file wave0.csv.
    #             Waveform shape: Blackman window with negative amplitude.
    # - (wave w1) using the waveform generation functionalities available in the AWG Sequencer
    #             language. Waveform shape: Gaussian function with positive amplitude.
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

    # Redefine the wave w1 in Python for later use in the plot
    width = AWG_N / 20
    waveform_1 = np.exp(
        -((np.linspace(-AWG_N / 2, AWG_N / 2, AWG_N)) ** 2) / (2 * width ** 2)
    )

    # Define an array of values that are used to generate wave w2
    waveform_2 = np.sin(np.linspace(0, 2 * np.pi, 96))

    # Fill the waveform values into the predefined program by inserting the array
    # as comma-separated floating-point numbers into awg_program.
    # Warning: Defining waveforms with the vect function can increase the code size
    #          considerably and should be used for short waveforms only.
    awg_program = awg_program.replace("_w2_", ",".join([str(x) for x in waveform_2]))

    # Replace the placeholder with the integer constant AWG_N.
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
        time.sleep(0.5)
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

    # Configure the Scope for measurement
    # 'channels/0/inputselect' : the input channel for the scope:
    #   0 - signal input 1
    daq.setInt("/%s/scopes/0/channels/0/inputselect" % (device), in_channel)
    # 'time' : timescale of the wave, sets the sampling rate to 1.8GHz/2**time.
    #   0 - sets the sampling rate to 1.8 GHz
    #   1 - sets the sampling rate to 900 MHz
    #   ...
    #   16 - sets the sampling rate to 27.5 kHz
    daq.setInt("/%s/scopes/0/time" % device, 0)
    # 'single' : only get a single scope shot.
    #   0 - take continuous shots
    #   1 - take a single shot

    # Disable the scope.
    daq.setInt("/%s/scopes/0/enable" % device, 0)
    # Configure the length of the scope shot.
    daq.setInt("/%s/scopes/0/length" % device, 8000)
    # Now configure the scope's trigger to get aligned data
    # 'trigenable' : enable the scope's trigger (boolean).
    daq.setInt("/%s/scopes/0/trigenable" % device, 1)
    # Specify the trigger channel:
    #
    # Here we trigger on the signal from UHF signal input 1. If the instrument has the DIG Option
    # installed we could trigger the scope using an AWG Trigger instead (see the `setTrigger(1);`
    # line in `awg_program` above).
    # 0:   Signal Input 1
    # 192: AWG Trigger 1
    trigchannel = 0
    daq.setInt("/%s/scopes/0/trigchannel" % device, trigchannel)
    if trigchannel == 0:
        # Trigger on the falling edge of the negative blackman waveform `w0` from our AWG program.
        daq.setInt("/%s/scopes/0/trigslope" % device, 2)
        daq.setDouble("/%s/scopes/0/triglevel" % device, -0.600)
        # Set hysteresis triggering threshold to avoid triggering on noise
        # 'trighysteresis/mode' :
        #  0 - absolute, use an absolute value ('scopes/0/trighysteresis/absolute')
        #  1 - relative, use a relative value ('scopes/0trighysteresis/relative') of the
        #      trigchannel's input range (0.1=10%).
        daq.setDouble("/%s/scopes/0/trighysteresis/mode" % device, 0)
        daq.setDouble("/%s/scopes/0/trighysteresis/relative" % device, 0.025)
        # Set a negative trigdelay to capture the beginning of the waveform.
        trigdelay = -1.0e-6
        daq.setDouble("/%s/scopes/0/trigdelay" % device, trigdelay)
    else:
        # Assume we're using an AWG Trigger, then the scope configuration is simple: Trigger on
        # rising edge.
        daq.setInt("/%s/scopes/0/trigslope" % device, 1)
        # Set trigdelay to 0.0: Start recording from when the trigger is activated.
        trigdelay = 0.0
        daq.setDouble("/%s/scopes/0/trigdelay" % device, trigdelay)
    trigreference = 0.0
    # The trigger reference position relative within the wave, a value of 0.5 corresponds to the
    # center of the wave.
    daq.setDouble("/%s/scopes/0/trigreference" % device, trigreference)
    # Set the hold off time in-between triggers.
    daq.setDouble("/%s/scopes/0/trigholdoff" % device, 0.025)

    # Set up the Scope Module.
    scopeModule = daq.scopeModule()
    scopeModule.set("mode", 1)
    scopeModule.subscribe(f"/{device}/scopes/0/wave")
    daq.setInt("/%s/scopes/0/single" % device, 1)

    scopeModule.execute()

    # Start the AWG in single-shot mode.
    # This is the preferred method of using the AWG: Run in single mode continuous waveform playback
    # is best achieved by using an infinite loop (e.g., while (true)) in the sequencer program.
    daq.set([[f"/{device}/awgs/0/single", 1], [f"/{device}/awgs/0/enable", 1]])
    daq.sync()

    # Start the scope...
    daq.setInt("/%s/scopes/0/enable" % device, 1)
    daq.sync()
    time.sleep(1.0)

    daq.setInt("/%s/awgs/0/userregs/0" % device, 1)

    # Read the scope data with timeout.
    local_timeout = 2.0
    records = 0
    while (records < 1) and (local_timeout > 0):
        time.sleep(0.1)
        local_timeout -= 0.1
        records = scopeModule.getInt("records")

    # Disable the scope.
    daq.setInt("/%s/scopes/0/enable" % device, 0)

    data_read = scopeModule.read(True)
    wave_nodepath = f"/{device}/scopes/0/wave"
    assert (
        wave_nodepath in data_read
    ), f"Error: The subscribed data `{wave_nodepath}` was returned."
    data = data_read[wave_nodepath][0][0]

    f_s = 1.8e9  # sampling rate of scope and AWG
    for i in range(0, len(data["channelenable"])):
        if data["channelenable"][i]:
            y_measured = data["wave"][i]
            x_measured = (
                np.arange(-data["totalsamples"], 0) * data["dt"]
                + (data["timestamp"] - data["triggertimestamp"]) / f_s
            )

    # Compare expected and measured signal
    full_scale = 0.75
    y_expected = (
        np.concatenate((waveform_0, waveform_1, waveform_2, waveform_3))
        * full_scale
        * amplitude
    )
    x_expected = np.linspace(0, len(y_expected) / f_s, len(y_expected))

    # Correlate measured and expected signal
    corr_meas_expect = np.correlate(y_measured, y_expected)
    index_match = np.argmax(corr_meas_expect)

    if plot:
        # The shift between measured and expected signal depends among other things on cable length.
        # We simply determine the shift experimentally and then plot the signals with an according
        # correction on the horizontal axis.
        x_shift = (
            index_match / f_s
            - trigreference * (x_measured[-1] - x_measured[0])
            + trigdelay
        )

        print("Plotting the expected and measured AWG signal.")
        x_unit = 1e-9
        plt.figure(1)
        plt.clf()
        plt.title("Measured and expected AWG Signals")
        plt.plot(x_measured / x_unit, y_measured, label="measured")
        plt.plot((x_expected + x_shift) / x_unit, y_expected, label="expected")
        plt.grid(True)
        plt.autoscale(axis="x", tight=True)
        plt.legend(loc="upper left")
        plt.xlabel("Time, relative to trigger (ns)")
        plt.ylabel("Voltage (V)")
        plt.draw()
        plt.show()

    # Normalize the correlation coefficient by the two waveforms and check they
    # agree to 95%.
    norm_correlation_coeff = corr_meas_expect[index_match] / np.sqrt(
        sum(y_measured ** 2) * sum(y_expected ** 2)
    )
    assert norm_correlation_coeff > 0.95, (
        "Detected a disagreement between the measured and expected signals, "
        f"normalized correlation coefficient: {norm_correlation_coeff}."
    )
    print(
        f"Measured and expected signals agree, normalized correlation coefficient: \
            {norm_correlation_coeff}."
    )


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
