function data = example_multidevice_sweep(device_ids, varargin)

% Zurich Instruments LabOne MATLAB API Example
%
% Demonstrate how to perform a frequency sweep on two synchronized devices using
% the MultiDeviceSync Module and ziDAQSweeper class/Sweeper Module.
%
% Copyright 2018 Zurich Instruments AG
%
% Run the example: Perform a frequency sweep on two devices and record
% demodulator data using ziPython's ziDAQSweeper module. The devices are first
% synchronized using the MultiDeviceSync Module, then the sweep is executed
% before stopping the synchronization.
%
% Requirements:
%   This example needs at least 2 UHFLIs, or 2 HF2LIs, or 2 MFLIs.
%   Hardware configuration: Connect signal output 1 of the first device to
%   signal input 1 of all devices using a splitter.
%
% Arguments:
%   device_ids (char cell array): The IDs of the devices to run the example with. For
%     example, {'dev1000','dev2000'}.
%   amplitude (float, optional): The amplitude to set on the signal output.
%   synchronize (bool, optional): Specify if multi-device synchronization will
%     be started and stopped before and after the sweep
%   server (char array, optional): The IP-address of the LabOne Data Server
%     Default is 'localhost'.
%
% Returns:
%   data (dict): A dictionary with all the data as returned from the sweeper
%   module. It contains all the demodulator data dictionaries and some
%   metainformation about the sweep.
%
% See the "LabOne Programming Manual" for further help, available:
%   - On Windows via the Start-Menu:
%     Programs -> Zurich Instruments -> Documentation
%   - On Linux in the LabOne .tar.gz archive in the "Documentation"
%     sub-folder.
%
% Define parameters relevant to this example. Default values specified by the
% inputParser below are overwritten if specified as name-value pairs via the
% `varargin` input argument.
%
% NOTE The possible choice of the parameters:
% - demod_rate (and the number of demods enabled=^length(demod_idx)),
% - event_frequency (the number of triggers we record per second),
% are highly constrained by the performance of the PC where the Data Server
% and Matlab API client are running. The values of the parameters set here are
% conservative. Much higher values can be obtained on state-of-the-art PCs
% (e.g., 400e3 demod_rate (2 or 3 demods) and event_frequency 5000 for UHF).
% Whilst experimenting with parameter values, it's advisable to monitor CPU
% load and memory usage.
p = inputParser;
isnonnegscalar = @(x) isnumeric(x) && isscalar(x) && (x > 0);
isbool = @(x) islogical(x);
is_text = @(x) ischar(x);
p.addParamValue('amplitude', 0.1, isnonnegscalar);
p.addParamValue('synchronize', 1, isbool);
p.addParamValue('server', 'localhost', is_text);
p.parse(varargin{:});
amplitude = p.Results.amplitude;
synchronize = p.Results.synchronize;
server_address = p.Results.server;

clear ziDAQ;

if ~exist('device_ids', 'var')
    error(['No list of device_ids specified. The first argument to the ' ...
           'example should be the device IDs on which to run the example, ' ...
           'e.g. ''dev1000'' or ''uhf-dev1000''.'])
end

% Check the ziDAQ MEX (DLL) and Utility functions can be found in Matlab's path.
if ~(exist('ziDAQ') == 3) && ~(exist('ziCreateAPISession', 'file') == 2)
    fprintf('Failed to either find the ziDAQ mex file or ziDevices() utility.\n')
    fprintf('Please configure your path using the ziDAQ function ziAddPath().\n')
    fprintf('This can be found in the API subfolder of your LabOne installation.\n');
    fprintf('On Windows this is typically:\n');
    fprintf('C:\\Program Files\\Zurich Instruments\\LabOne\\API\\MATLAB2012\\\n');
    return
end

% Connection to the data server and instruments
deviceSerials = cellfun(@(devId) lower(ziDAQ('discoveryFind', devId)), device_ids, 'UniformOutput', false);
deviceProps = cellfun(@(devSer) ziDAQ('discoveryGet', devSer), deviceSerials);

% Switching between MFLI, HF2LI, and UHFLI
leaderDeviceType = deviceProps(1).devicetype;

if all(arrayfun(@(prop) isequal(leaderDeviceType, prop.devicetype) && strcmpi(leaderDeviceType, 'UHFLI'), deviceProps))
    ziDAQ('connect', server_address', 8004, 6);
    arrayfun(@(prop) ziDAQ('connectDevice', lower(prop.deviceid), prop.interfaces{1}), deviceProps);
elseif all(arrayfun(@(prop) ~isempty(strfind(prop.devicetype, 'MF')), deviceProps))
    ziDAQ('connect', server_address', 8004, 6);
    arrayfun(@(prop) ziDAQ('connectDevice', lower(prop.deviceid), '1GbE'), deviceProps);
elseif all(arrayfun(@(prop) ~isempty(strfind(prop.devicetype, 'HF2')), deviceProps))
    ziDAQ('connect', server_address', 8005, 1);
    arrayfun(@(prop) ziDAQ('connectDevice', lower(prop.deviceid), 'USB'), deviceProps);
else
    error('This example needs at least 2 MFLI instruments, or 2 HF2LI instruments, or 2 UHFLI instruments');
end

% Check version compatibility between Data Server and API
ziApiServerVersionCheck();

% Create a base configuration on all devices: Disable all available outputs, awgs, demods, scopes,...
for i = 1:length(device_ids)
    ziDisableEverything(device_ids{i});
end

% Now configure the instrument for this experiment. The following channels
% and indices work on all device configurations. The values below may be
% changed if the instrument has multiple input/output channels and/or either
% the Multifrequency or Multidemodulator options installed.
out_channel = 0;
in_channel = 0;
demod_index = 0;
osc_index = 0;
demod_rate = 10e3;
time_constant = 0.01;
for i = 1:length(device_ids)
    out_mixer_channel = str2double(ziGetDefaultSigoutMixerChannel(deviceProps(i), out_channel));
    ziDAQ('setInt', sprintf('/%s/sigins/%d/ac', device_ids{i}, in_channel), 0);
    ziDAQ('setDouble', sprintf('/%s/sigins/%d/range', device_ids{i}, in_channel), 2*amplitude);
    ziDAQ('setInt', sprintf('/%s/demods/%d/enable', device_ids{i}, demod_index), 1);
    ziDAQ('setDouble', sprintf('/%s/demods/%d/rate', device_ids{i}, demod_index), demod_rate);
    ziDAQ('setInt', sprintf('/%s/demods/%d/adcselect', device_ids{i}, demod_index), in_channel);
    ziDAQ('setInt', sprintf('/%s/demods/%d/order', device_ids{i}, demod_index), 4);
    ziDAQ('setDouble', sprintf('/%s/demods/%d/timeconstant', device_ids{i}, demod_index), time_constant);
    ziDAQ('setInt', sprintf('/%s/demods/%d/oscselect', device_ids{i}, demod_index), osc_index);
    ziDAQ('setInt', sprintf('/%s/demods/%d/harmonic', device_ids{i}, demod_index), 1);
    ziDAQ('setInt', sprintf('/%s/sigouts/%d/on', device_ids{i}, out_channel), 1);
    ziDAQ('setInt', sprintf('/%s/sigouts/%d/enables/%d', device_ids{i}, out_channel, out_mixer_channel), 1);
    ziDAQ('setDouble', sprintf('/%s/sigouts/%d/range', device_ids{i}, out_channel), 2*amplitude);
    ziDAQ('setDouble', sprintf('/%s/sigouts/%d/amplitudes/%d', device_ids{i}, out_channel, out_mixer_channel), amplitude);
end

% Perform a global synchronisation between the device and the data server:
% Ensure that 1. the settings have taken effect on the device before issuing
% the poll() command and 2. clear the API's data buffers.
ziDAQ('sync');

% Prepare a string to tell the sync module which devices should be synchronized (should not contain spaces)
devices = strjoin(deviceSerials, ',');

% Here we synchronize all the devices as defined in the comma separated string "devices"
if synchronize
    fprintf('Synchronizing devices %s ...\n', devices);
    multiDeviceSyncModule = ziDAQ('multiDeviceSyncModule');
    ziDAQ('set', multiDeviceSyncModule, 'start', 0);
    ziDAQ('set', multiDeviceSyncModule, 'group', 0);
    ziDAQ('execute', multiDeviceSyncModule);
    ziDAQ('set', multiDeviceSyncModule, 'devices', devices);
    ziDAQ('set', multiDeviceSyncModule, 'start', 1);

    timeout = 20;
    tstart = now();
    while true
        pause(0.2);
        status = ziDAQ('getInt', multiDeviceSyncModule, 'status');
        assert (status ~= -1, 'Error during device sync');
        if status == 2
            break
        end
        assert ((now() - tstart) * 24 * 60 * 60  < timeout, 'Timeout during device sync');
    end
end

fprintf('Start sweeper\n');
% Create an instance of the Sweeper Module.
sweeper = ziDAQ('sweep');
% Configure the Sweeper Module's parameters.
% Set the device that will be used for the sweep - this parameter must be set.
ziDAQ('set', sweeper, 'device', device_ids{1});
% Specify the `gridnode`: The instrument node that we will sweep, the device
% setting corresponding to this node path will be changed by the sweeper.
ziDAQ('set', sweeper, 'gridnode', sprintf('oscs/%d/freq', osc_index));
% Set the `start` and `stop` values of the gridnode value interval we will use in the sweep.
ziDAQ('set', sweeper, 'start', 100);
ziDAQ('set', sweeper, 'stop', 500e3);
% Set the number of points to use for the sweep, the number of gridnode
% setting values will use in the interval (`start`, `stop`).
samplecount = 100;
ziDAQ('set', sweeper, 'samplecount', samplecount);
% Specify logarithmic spacing for the values in the sweep interval.
ziDAQ('set', sweeper, 'xmapping', 1);
% Automatically control the demodulator bandwidth/time constants used.
% 0=manual, 1=fixed, 2=auto
% Note: to use manual and fixed, bandwidth has to be set to a value > 0.
ziDAQ('set', sweeper, 'bandwidthcontrol', 2);
% Sets the bandwidth overlap mode (default 0). If enabled, the bandwidth of
% a sweep point may overlap with the frequency of neighboring sweep
% points. The effective bandwidth is only limited by the maximal bandwidth
% setting and omega suppression. As a result, the bandwidth is independent
% of the number of sweep points. For frequency response analysis bandwidth
% overlap should be enabled to achieve maximal sweep speed (default: 0). 0 =
% Disable, 1 = Enable.
ziDAQ('set', sweeper, 'bandwidthoverlap', 0);

% Sequential scanning mode (as opposed to binary or bidirectional).
ziDAQ('set', sweeper, 'scan', 0);
% We don't require a fixed settling/time since there is no DUT
% involved in this example's setup (only a simple feedback cable), so we set
% this to zero. We need only wait for the filter response to settle,
% specified via settling/inaccuracy.
ziDAQ('set', sweeper, 'settling/time', 0);
% The settling/inaccuracy' parameter defines the settling time the
% sweeper should wait before changing a sweep parameter and recording the next
% sweep data point. The settling time is calculated from the specified
% proportion of a step response function that should remain. The value
% provided here, 0.001, is appropriate for fast and reasonably accurate
% amplitude measurements. For precise noise measurements it should be set to
% ~100n.
% Note: The actual time the sweeper waits before recording data is the maximum
% time specified by settling/time and defined by
% settling/inaccuracy.
ziDAQ('set', sweeper, 'settling/inaccuracy', 0.001);
% Set the minimum time to record and average data to 10 demodulator
% filter time constants.
ziDAQ('set', sweeper, 'averaging/tc', 10);
% Minimal number of samples that we want to record and average is 100. Note,
% the number of samples used for averaging will be the maximum number of
% samples specified by either averaging/tc or averaging/sample.
ziDAQ('set', sweeper, 'averaging/sample', 10);

% Now subscribe to the nodes from which data will be recorded. Note, this is
% not the subscribe from ziDAQServer; it is a Module subscribe. The Sweeper
% Module needs to subscribe to the nodes it will return data for.x
paths = cell(length(device_ids));
for i = 1:length(device_ids)
    paths{i} = sprintf('/%s/demods/%d/sample', device_ids{i}, demod_index);
end
for i = 1:length(paths)
    ziDAQ('subscribe', sweeper, paths{i});
end

% Start the Sweeper's thread.
ziDAQ('execute', sweeper);

start = now();
timeout = 60;  % [s]
while ~ziDAQ('finished', sweeper)  % Wait until the sweep is complete, with timeout.
    pause(0.5);
    progress = ziDAQ('progress', sweeper);
    fprintf('Individual sweep progress: %d%%\n', round(progress*100));
    % Here we could read intermediate data via:
    % data = ziDAQ('read', sweeper)...
    % and process it while the sweep is completing.
    % if device in data:
    % ...
    if (now() - start) * 24 * 60 * 60 > timeout
        % If for some reason the sweep is blocking, force the end of the
        % measurement.
        fprintf('\nSweep still not finished, forcing finish...\n');
        ziDAQ('finish', sweeper);
    end
end
fprintf('');

% Read the sweep data. This command can also be executed whilst sweeping
% (before finished() is True), in this case sweep data up to that time point
% is returned. It's still necessary still need to issue read() at the end to
% fetch the rest.
data = ziDAQ('read', sweeper);
for i = 1:length(paths)
    ziDAQ('unsubscribe', sweeper, paths{i});
end

% Stop the sweeper module and clear the memory.
% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', sweeper);

% Check the data returned is non-empty.
assert (~isempty(data), 'read() returned an empty data, did you subscribe to any paths?');
% Note: data could be empty if no data arrived, e.g., if the demods were
% disabled or had rate 0.
for i = 1:length(paths)
    assert (ziCheckPathInData(data, paths{i}), ['No sweep data in data : it has no key ' 'paths{i}']);
end

figure(1); cla;
plot_style = {'r-', 'b-', 'g-', 'k-'};
for i = 1:length(device_ids)
    frequency = data.(lower(device_ids{i})).demods.sample{demod_index + 1}.frequency;
    R = data.(lower(device_ids{i})).demods.sample{demod_index + 1}.r;
    h(i) = plot(frequency, R, plot_style{i});
    set(h(i), 'LineWidth', 2.0);
    set(gca, 'XScale', 'log');
    xlabel('Frequency [Hz]');
    ylabel('Amplitude [V]');
    grid on;
    hold on;
end

if synchronize
    fprintf('Teardown: Clearing the multiDeviceSyncModule.\n');
    ziDAQ('set', multiDeviceSyncModule, 'start', 0);
    timeout = 2;
    tstart = now();
    while true
        pause(0.1);
        status = ziDAQ('getInt', multiDeviceSyncModule,'status');
        assert (status ~= -1, 'Error during device sync stop');
        if status == 0
            break;
        end
        if (now() - tstart) * 24 * 60 * 60 > timeout
            fprintf('Warning: Timeout during device sync stop. The devices might still be synchronized.');
            break;
        end
    end
    % Release module resources. Especially important if modules are created
    % inside a loop to prevent excessive resource consumption.
    ziDAQ('clear', multiDeviceSyncModule);
end
