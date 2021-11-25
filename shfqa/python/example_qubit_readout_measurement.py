# Copyright 2021 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Does a parallel read-out of 8 qubits.

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
    --no-plot                 Hide plot of the recorded data.

Returns:
    dict              complex readout data

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
import zhinst.utils
from zhinst.deviceutils import SHFQA
import helper_qubit_readout as helper
import helper_commons


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = 8004,
    plot: bool = True,
):
    """run the example."""

    # connect device
    apilevel_example = 6
    (daq, _, _) = zhinst.utils.create_api_session(
        device_id, apilevel_example, server_host=server_host, server_port=server_port
    )

    shfqa = SHFQA(device_id, daq)

    # define parameters
    channel_index = 0
    num_qubits = 8
    num_readouts = 100

    # configure inputs and outputs
    shfqa.configure_channel(
        channel_index,
        center_frequency=5e9,
        input_range=0,
        output_range=-5,
        mode="readout",
    )

    # generate and upload waveforms
    scaling = 0.9 / num_qubits
    readout_pulses = helper_commons.generate_flat_top_gaussian(
        frequencies=np.linspace(32e6, 230e6, num_qubits),
        pulse_duration=500e-9,
        rise_fall_time=10e-9,
        sampling_rate=SHFQA.SAMPLING_FREQUENCY,
        scaling=scaling,
    )
    shfqa.write_to_waveform_memory(channel_index, waveforms=readout_pulses)

    # configure result logger and weighted integration
    weights = helper.generate_integration_weights(readout_pulses)
    shfqa.configure_weighted_integration(
        channel_index,
        weights,
        # compensation for the delay between generator output and input of the integration unit
        integration_delay=200e-9,
    )
    shfqa.configure_result_logger(channel_index, result_length=num_readouts)

    # configure sequencer
    shfqa.configure_sequencer_triggering(channel_index, aux_trigger="software_trigger0")
    seqc_program = helper.generate_sequencer_program(
        num_measurements=num_readouts, task="dig_trigger_play_all"
    )
    shfqa.load_sequencer_program(channel_index, sequencer_program=seqc_program)

    # run experiment
    shfqa.enable_result_logger(channel_index)
    shfqa.enable_sequencer(channel_index)
    shfqa.start_continuous_sw_trigger(num_triggers=num_readouts, wait_time=2e-3)

    # get and plot results
    readout_results = shfqa.get_result_logger_data(channel_index)

    if plot:
        helper.plot_readout_results(readout_results[:num_qubits])

    return readout_results[:num_qubits]


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
