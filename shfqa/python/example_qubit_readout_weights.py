# Copyright 2021 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Measures the integration weights for a qubit readout assuming 8 qubits and using gaussian flat
top pulses.

Requirements:
    * LabOne Version >= 21.08
    * Instruments:
        1 x SHFQA Instrument
    * Loopback configuration between input and output of channel 0

Usage:
    example_qubit_readout_measurement.py [options] <device_id>
    example_qubit_readout_measurement.py -h | --help

Arguments:
    <device_id>  The ID of the device to run the example with. [device_type: SHFQA]

Options:
    -h --help                 Show this screen.
    -s --server_host IP       Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT     Port number of the data server [default: 8004]
    -a --api_level  LEVEL     api level of the API session to be instantiated in this example.
                              [default: 6]
    -i --interface INTERFACE  interface through which the device is connected to the host, can be
                              "1gbe" or "usb"str="1gbe". [default: 1gbe]
    --no-plot                 Hide plot of the recorded data.

Returns:
    dict              integration weights for each qubit

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
import shf_utils
import helper_qubit_readout as helper
import helper_commons
from zhinst.ziPython import ziDAQServer


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = 8004,
    api_level: int = 6,
    interface: str = "1gbe",
    plot: bool = True,
):
    """run the example."""

    daq = ziDAQServer(server_host, server_port, api_level)
    daq.connectDevice(device_id, interface)

    shfqa = shf_utils.Shfqa(device_id, daq)

    # define parameters
    channel_index = 0
    num_qubits = 8
    readout_duration = 600e-9
    num_segments = 2
    num_averages = 50
    num_measurements = num_segments * num_averages
    scope_channel = 0

    # configure inputs and outputs
    shfqa.configure_channel(
        channel_index,
        center_frequency=5e9,
        input_range=0,
        output_range=-5,
        mode="readout",
    )

    # configure scope
    shfqa.configure_scope(
        input_select={scope_channel: f"channel{channel_index}_signal_input"},
        num_samples=int(readout_duration * shf_utils.Shfqa.SAMPLING_FREQUENCY),
        trigger_input=f"channel{channel_index}_sequencer_monitor0",
        num_segments=num_segments,
        num_averages=num_averages,
        # compensation for the delay between generator output and input of the integration unit
        trigger_delay=200e-9,
    )

    # generate and upload waveforms
    excitation_pulses = helper_commons.generate_flat_top_gaussian(
        frequencies=np.linspace(2e6, 32e6, num_qubits),
        pulse_duration=500e-9,
        rise_fall_time=10e-9,
        sampling_rate=shf_utils.Shfqa.SAMPLING_FREQUENCY,
    )
    shfqa.write_to_waveform_memory(channel_index, waveforms=excitation_pulses)

    # configure sequencer
    shfqa.configure_sequencer_triggering(channel_index, aux_trigger="software_trigger0")

    # run experiment measurement loop
    weights = {}
    for i in range(num_qubits):

        print(f"Measuring qubit {i}.")

        # upload sequencer program
        seqc_program = helper.generate_sequencer_program(
            num_measurements=num_measurements,
            task="dig_trigger_play_single",
            waveform_slot=i,
        )
        shfqa.load_sequencer_program(channel_index, sequencer_program=seqc_program)

        # start a measurement
        shfqa.enable_scope()
        shfqa.enable_sequencer(channel_index)
        shfqa.start_continuous_sw_trigger(
            num_triggers=num_measurements, wait_time=readout_duration
        )

        # get results to calculate weights and plot data
        scope_data, *_ = shfqa.get_scope_data(time_out=5)

        weights[i] = helper.calculate_readout_weights(scope_data[scope_channel])

        if plot:
            helper.plot_scope_data_for_weights(
                scope_data[scope_channel],
                sampling_rate=shf_utils.Shfqa.SAMPLING_FREQUENCY,
            )
            helper.plot_readout_weights(
                weights[i], sampling_rate=shf_utils.Shfqa.SAMPLING_FREQUENCY
            )

    return weights


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
