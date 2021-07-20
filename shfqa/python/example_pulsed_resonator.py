# Copyright 2021 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Run a frequency sweep with a SHFQA using an external trigger (trigger in 1 A)

Requirements:
    * LabOne Version >= 21.08
    * Instruments:
        1 x SHFQA Instrument
    * Signal output 0 connected to signal input 0 with a BNC cable.

Usage:
    example_pulsed_resonator.py [options] <device_id>
    example_pulsed_resonator.py -h | --help

Arguments:
    <device_id>  The ID of the device to run the example with. [device_type: SHFQA]

Options:
    -h --help                           Show this screen.
    -s --server_host IP    Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT  Port number of the data server [default: 8004]
    --trigger_source TRIGGER_SOURCE     Source channel for the trigger
                                        [default: channel0_trigger_input0]
    --no-loopback                       Do not use a loopback signal for triggering. An external trigger
                                        of software trigger is required
    --spectroscopy_delay DELAY          The time delay between trigger and the beginning of the IN signal
                                        integration (s) [default: 0.0]
    --envelope_delay DELAY              The time delay between trigger and propagation of the OUT signal (s)
                                        [default: 0.0]
    --no-scope                          Validate the recorded pulse in the input channel with the scope
                                        and calculate the optimal spectroscopy delay
    --no-plot                           Hide plot of the recorded data.

Returns:
    dict  Results of the frequency sweep.

Raises:
    Exception     If the specified device does not match the requirements.
    RuntimeError  If the device is not "discoverable" from the API.

See the "LabOne Programming Manual" for further help, available:
    - On Windows via the Start-Menu:
      Programs -> Zurich Instruments -> Documentation
    - On Linux in the LabOne .tar.gz archive in the "Documentation"
      sub-folder.
"""

import numpy as np
import matplotlib.pyplot as plt
import zhinst.utils
from zhinst.utils.shf_sweeper import (
    ShfSweeper,
    AvgConfig,
    RfConfig,
    SweepConfig,
    TriggerConfig,
    EnvelopeConfig,
)
import shf_utils
import helper_resonator
import helper_commons
import shf_utils


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = 8004,
    trigger_source: str = "channel0_trigger_input0",
    loopback: bool = True,
    spectroscopy_delay: float = 0.0,
    envelope_delay: float = 0.0,
    scope: bool = True,
    plot: bool = True,
):
    """run the example."""

    # connect device
    apilevel_example = 6
    (daq, dev, _) = zhinst.utils.create_api_session(
        device_id, apilevel_example, server_host=server_host, server_port=server_port
    )

    # use the marker output via loopback to trigger the measurement
    # remove this code when using a real external trigger (e.g. an HDAWG)
    if loopback:
        # force the trigger channel
        trigger_source = "channel0_trigger_input0"
        # enable the loopback trigger
        helper_resonator.set_trigger_loopback(daq, dev)

    # instantiate ShfSweeper
    sweeper = ShfSweeper(daq, dev)

    # generate the complex pulse envelope with a zero modulation frequency
    envelope_duration = 1.0e-6
    envelope_rise_fall_time = 0.05e-6
    envelope_frequencies = [0]
    flat_top_gaussians = helper_commons.generate_flat_top_gaussian(
        envelope_frequencies,
        envelope_duration,
        envelope_rise_fall_time,
        shf_utils.Shfqa.SAMPLING_FREQUENCY,
        scaling=1,
    )
    flat_top_gaussians_key = 0
    pulse_envelope = flat_top_gaussians[flat_top_gaussians_key]

    # configure sweeper
    sweep_config = SweepConfig(
        start_freq=-200e6,
        stop_freq=300e6,
        num_points=51,
        mapping="linear",
        oscillator_gain=0.8,
    )
    avg_config = AvgConfig(
        integration_time=envelope_duration,
        num_averages=2,
        mode="sequential",
        integration_delay=spectroscopy_delay,
    )
    rf_config = RfConfig(channel=0, input_range=0, output_range=0, center_freq=4e9)
    trig_config = TriggerConfig(source=trigger_source, level=0)
    envelope_config = EnvelopeConfig(waveform=pulse_envelope, delay=envelope_delay)

    sweeper.configure(sweep_config, avg_config, rf_config, trig_config, envelope_config)

    # set to device, can also be ignored but is needed to verify envelope before sweep
    sweeper.set_to_device()

    # turn on the input / output channel
    daq.setInt(f"/{dev}/qachannels/{rf_config.channel}/input/on", 1)
    daq.setInt(f"/{dev}/qachannels/{rf_config.channel}/output/on", 1)
    daq.sync()

    if scope:
        # verify the spectroscopy pulse using the SHFQA scope before starting the sweep
        # NOTE: this only works if the device under test transmits the signal at the
        # selected center frequency. To obtain the actual pulse shape, the user must
        # connect the output of the SHFQA directly to the input on the same channel.
        daq.setDouble(f"/{dev}/qachannels/{rf_config.channel}/oscs/0/freq", 0)
        scope_trace = helper_resonator.measure_resonator_pulse_with_scope(
            daq,
            dev,
            channel=rf_config.channel,
            trigger_input=trig_config.source,
            pulse_length_seconds=envelope_duration,
            envelope_delay=envelope_delay,
        )
        if plot:
            helper_resonator.plot_resonator_pulse_scope_trace(scope_trace)

        # simple filter window size for filtering the scope data
        window_s = 4

        # apply the filter to both the intial pulse and the one observed with the scope
        # to introduce the same amount of 'delay'
        pulse_smooth = np.convolve(
            np.abs(pulse_envelope), np.ones(window_s) / window_s, mode="same"
        )
        pulse_diff = np.diff(np.abs(pulse_smooth))
        sync_tick = np.argmax(pulse_diff)

        scope_smooth = np.diff(np.abs(scope_trace))
        scope_diff = np.convolve(
            scope_smooth, np.ones(window_s) / window_s, mode="same"
        )
        sync_tack = np.argmax(scope_diff)

        delay_in_ns = (
            1.0e9 * (sync_tack - sync_tick) / shf_utils.Shfqa.SAMPLING_FREQUENCY
        )
        delay_in_ns = 2 * ((delay_in_ns + 1) // 2)  # round up to the 2ns resolution
        print(f"delay between generator and monitor: {delay_in_ns} ns")
        print(f"Envelope delay: {envelope_delay * 1e9:.0f} ns")
        if spectroscopy_delay * 1e9 == delay_in_ns + (envelope_delay * 1e9):
            print("Spectroscopy delay and envelope perfectly timed!")
        else:
            print(
                f"Consider setting the spectroscopy delay to [{(envelope_delay + (delay_in_ns * 1e-9))}] "
            )
            print("to exactly integrate the envelope.")

        if plot:
            time_ticks_scope = (
                1.0e6
                * np.array(range(len(scope_diff)))
                / shf_utils.Shfqa.SAMPLING_FREQUENCY
            )
            time_ticks_pulse = (
                1.0e6
                * np.array(range(len(pulse_diff)))
                / shf_utils.Shfqa.SAMPLING_FREQUENCY
            )
            plt.plot(time_ticks_scope, scope_diff)
            plt.plot(time_ticks_pulse, pulse_diff)
            plt.title("Pulse gradient")
            plt.xlabel(r"t [$\mu$s]")
            plt.legend(["scope", "pulse"])
            plt.grid()
            plt.show()

    # start a sweep
    result = sweeper.run()
    print("Keys in the ShfSweeper result dictionary: ")
    print(result.keys())

    # alternatively, get result after sweep
    result = sweeper.get_result()
    num_points_result = len(result["vector"])
    print(f"Measured at {num_points_result} frequency points.")

    # simple plot over frequency
    if plot:
        sweeper.plot()

    if loopback:
        helper_resonator.clear_trigger_loopback(daq, dev)

    return result


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
