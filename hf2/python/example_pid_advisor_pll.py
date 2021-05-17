# Copyright 2017 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to connect to a Zurich Instruments HF2 Lock-in Amplifier and use
the PID Advisor to set up an internal PLL control loop using ziDAQServer's
pidAdvisor Module.
Connect to a Zurich Instruments HF2 and obtain optimized P, I, and D parameters for
an internal PLL loop using ziDAQServer's pidAdvisor module.

Requirements:
    * LabOne Version >= 21.02
    * Instruments:
        1 x HF2 Instrument with the PLL option
    * Signal output 1 connected to signal input 1 with a BNC cable.

Usage:
    example_awg_sourcefile.py [options] <device_id>
    example_awg_sourcefile.py -h | --help

Arguments:
    <device_id>  The ID of the device to run the example with. [device_type: HF2(PLL)]

Options:
    -h --help                 Show this screen.
    -p --plot                 create a plot.

Returns:
      result (dict): A dictionary containing the PID Advisor result.

Raises:
    Exception     If the specified device does not match the requirements.
    RuntimeError  If the device is not "discoverable" from the API.

See the "LabOne Programming Manual" for further help, available:
    - On Windows via the Start-Menu:
      Programs -> Zurich Instruments -> Documentation
    - On Linux in the LabOne .tar.gz archive in the "Documentation"
      sub-folder.
"""

import time
import numpy as np
import zhinst.utils
import matplotlib.pyplot as plt


def run_example(device_id: str, plot: bool = False):
    """run the example."""

    # The API level supported by this example. Note, the HF2 data server
    # only supports API Level 1.
    apilevel_example = 1
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    # - the device's discovery properties.
    err_msg = (
        "This example only supports HF2 Instruments with the PLL Option installed."
    )
    (daq, device, props) = zhinst.utils.create_api_session(
        device_id,
        apilevel_example,
        required_devtype="HF2",
        required_options=["PLL"],
        required_err_msg=err_msg,
    )
    zhinst.utils.api_server_version_check(daq)

    # Create a base configuration: Disable all available outputs, awgs, demods, scopes,...
    zhinst.utils.disable_everything(daq, device)

    # Define configuration and configure the device.
    # PID configuration.
    target_bw = 10e3  # Target bandwidth (Hz).
    pll_index = 0  # PLL index.
    center_frequency = 1e6
    out_channel = 0
    osc_index = 1
    # Get the value of the instrument's default Signal Output mixer channel.
    out_mixer_channel = zhinst.utils.default_output_mixer_channel(props)
    amplitude = 1.0

    # Now configure the settings relevant to this experiment
    exp_setting = [
        ["/%s/oscs/%d/freq" % (device, osc_index), center_frequency],
        ["/%s/sigouts/%d/on" % (device, out_channel), True],
        ["/%s/sigouts/%d/enables/%d" % (device, out_channel, out_mixer_channel), True],
        ["/%s/sigouts/%d/range" % (device, out_channel), 1.0],
        [
            "/%s/sigouts/%d/amplitudes/%d" % (device, out_channel, out_mixer_channel),
            amplitude,
        ],
    ]
    daq.set(exp_setting)

    # Perform a global synchronisation between the device and the data server:
    # Ensure that the settings have taken effect on the device before starting the pidAdvisor.
    daq.sync()

    # set up PID Advisor
    pid_advisor = daq.pidAdvisor()

    # Turn off auto-calc on param change. Enabled
    # auto calculation can be used to automatically
    # update response data based on user input.
    pid_advisor.set("auto", False)
    pid_advisor.set("device", device)
    pid_advisor.set("pid/targetbw", target_bw)

    # PID advising mode (bit coded)
    # bit 0: optimize/tune P
    # bit 1: optimize/tune I
    # bit 2: optimize/tune D
    # Example: mode = 7: Optimize/tune PID
    pid_advisor.set("pid/mode", 7)

    # PID index to use (first PLL of device: 0)
    pid_advisor.set("index", pll_index)

    # DUT model
    # source = 1: Lowpass first order
    # source = 2: Lowpass second order
    # source = 3: Resonator frequency
    # source = 4: Internal PLL
    # source = 5: VCO
    # source = 6: Resonator amplitude
    dut_source = 4
    pid_advisor.set("dut/source", dut_source)

    if dut_source == 4:
        # HF2: Since the PLL and PID are 2 separate hardware units on the device, we need to
        # additionally specify that the PID Advisor should model the HF2's PLL.
        pid_advisor.set("pid/type", "pll")
        # Note: The PID Advisor is appropriate for optimizing the HF2's PLL parameters (pid/type set
        # to 'pll') or the HF2's PID parameters (pid/type set to 'pid').

    # IO Delay of the feedback system describing the earliest response
    # for a step change. This parameter does not affect the shape of
    # the DUT transfer function
    pid_advisor.set("dut/delay", 0.0)

    # Other DUT parameters (not required for the internal PLL model)
    # pid_advisor.set('dut/gain', 1.0)
    # pid_advisor.set('dut/bw', 1000)
    # pid_advisor.set('dut/fcenter', 15e6)
    # pid_advisor.set('dut/damping', 0.1)
    # pid_advisor.set('dut/q', 10e3)

    # Start values for the PID optimization. Zero
    # values will imitate a guess. Other values can be
    # used as hints for the optimization process.
    pid_advisor.set("pid/p", 0)
    pid_advisor.set("pid/i", 0)
    pid_advisor.set("pid/d", 0)

    # Start the module thread
    pid_advisor.execute()

    # Advise
    pid_advisor.set("calculate", 1)
    print("Starting advising. Optimization process may run up to a minute...")
    calculate = 1

    t_start = time.time()
    t_timeout = t_start + 90
    while calculate == 1:
        time.sleep(0.1)
        calculate = pid_advisor.getInt("calculate")
        progress = pid_advisor.progress()
        print(f"Advisor progress: {progress[0]:.2%}.", end="\r")
        if time.time() > t_timeout:
            pid_advisor.finish()
            raise Exception("PID advising failed due to timeout.")
    print("")
    print(f"Advice took {time.time() - t_start:0.1f} s.")

    # Get all calculated parameters.
    result = pid_advisor.get("*", True)
    # Check that the dictionary returned by poll contains the data that are needed.
    assert result, "pidAdvisor returned an empty data dictionary?"

    if result is not None:
        # Now copy the values from the PID Advisor to the device's PLL.
        pid_advisor.set("todevice", 1)
        # Note: On HF2 devices the PLL is an additional hardware entity on the device (it is not
        # combined on the device with the PID), so we need to copy the parameters to the appropriate
        # nodes in the PLLS device branch, not to the PIDS branch.
        #
        # Let's have a look at the optimised gain parameters.
        p_advisor = result["/pid/p"][0]
        i_advisor = result["/pid/i"][0]
        d_advisor = result["/pid/d"][0]
        print(
            f"The pidAdvisor calculated the following gains, P: {p_advisor}, I: {i_advisor}, D: \
                {d_advisor}."
        )

    if plot:

        plt.close("all")
        bode_complex_data = result["/bode"][0]["x"] + 1j * result["/bode"][0]["y"]
        bode_grid = result["/bode"][0]["grid"]

        step_x = result["/step"][0]["x"]
        step_grid = result["/step"][0]["grid"]

        bw_advisor = result["/bw"][0]

        _, axes = plt.subplots(2, 1)
        axes[0].plot(bode_grid, 20 * np.log10(np.abs(bode_complex_data)))
        axes[0].set_xscale("log")
        axes[0].grid(True)
        axes[0].set_title(
            r"Model response for internal PLL with "
            "P = %0.1f, I = %0.1f,\n"
            "D = %0.5f and bandwidth %0.1f kHz"
            % (p_advisor, i_advisor, d_advisor, bw_advisor * 1e-3)
        )
        axes[0].set_ylabel("Bode Gain (dB)")
        axes[0].autoscale(enable=True, axes="x", tight=True)

        axes[1].plot(bode_grid, np.angle(bode_complex_data) / np.pi * 180)
        axes[1].set_xscale("log")
        axes[1].grid(True)
        axes[1].set_xlabel("Frequency (Hz)")
        axes[1].set_ylabel("Bode Phase (deg)")
        axes[1].autoscale(enable=True, axis="x", tight=True)

        _, axis = plt.subplots(1, 1)
        axis.plot(step_grid * 1e6, step_x)
        axis.grid(True)
        axis.set_title(
            r"Step response for internal PLL with "
            "P = %0.1f, I = %0.1f,\nD = %0.5f and bandwidth %0.1f kHz"
            % (p_advisor, i_advisor, d_advisor, bw_advisor * 1e-3)
        )
        axis.set_xlabel(r"Time ($\mu$s)")
        axis.set_ylabel(r"Step Response")
        axis.autoscale(enable=True, axis="x", tight=True)
        axis.set_ylim([0.0, 1.05])
        plt.draw()
        plt.show()

    return result


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
