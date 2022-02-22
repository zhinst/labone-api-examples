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
import zhinst.deviceutils.shfqa as shfqa_utils
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

    # define parameters
    channel_index = 0
    num_qubits = 8
    num_readouts = 100

    # configure inputs and outputs
    shfqa_utils.configure_channel(
        daq,
        device_id,
        channel_index,
        center_frequency=5e9,
        input_range=0,
        output_range=-5,
        mode="readout",
    )
    # enable qachannel
    path = f"/{device_id}/qachannels/{channel_index}/"
    daq.setInt(path + "input/on", 1)
    daq.setInt(path + "output/on", 1)

    # generate and upload waveforms
    scaling = 0.9 / num_qubits
    readout_pulses = helper_commons.generate_flat_top_gaussian(
        frequencies=np.linspace(32e6, 230e6, num_qubits),
        pulse_duration=500e-9,
        rise_fall_time=10e-9,
        sampling_rate=shfqa_utils.SHFQA_SAMPLING_FREQUENCY,
        scaling=scaling,
    )
    shfqa_utils.write_to_waveform_memory(
        daq, device_id, channel_index, waveforms=readout_pulses
    )

    # configure result logger and weighted integration
    weights = helper.generate_integration_weights(readout_pulses)
    shfqa_utils.configure_weighted_integration(
        daq,
        device_id,
        channel_index,
        weights=weights,
        # compensation for the delay between generator output and input of the integration unit
        integration_delay=200e-9,
    )
    shfqa_utils.configure_result_logger_for_readout(
        daq,
        device_id,
        channel_index,
        result_source="result_of_integration",
        result_length=num_readouts,
    )

    # configure sequencer
    shfqa_utils.configure_sequencer_triggering(
        daq, device_id, channel_index, aux_trigger="software_trigger0"
    )
    seqc_program = helper.generate_sequencer_program(
        num_measurements=num_readouts, task="dig_trigger_play_all"
    )
    shfqa_utils.load_sequencer_program(
        daq, device_id, channel_index, sequencer_program=seqc_program
    )

    # run experiment
    shfqa_utils.enable_result_logger(daq, device_id, channel_index, mode="readout")
    shfqa_utils.enable_sequencer(daq, device_id, channel_index, single=1)
    # Note: software triggering is used for illustration purposes only. Use a real
    # trigger source for actual experiments
    shfqa_utils.start_continuous_sw_trigger(
        daq, device_id, num_triggers=num_readouts, wait_time=2e-3
    )

    # get and plot results
    readout_results = shfqa_utils.get_result_logger_data(
        daq, device_id, channel_index, mode="readout"
    )

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
