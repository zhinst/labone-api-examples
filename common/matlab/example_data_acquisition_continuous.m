function [data] = example_data_acquisition_continuous(device_id, varargin)
% EXAMPLE_DATA_ACQUISITION_CONTINUOUS Record data continuously using the Data Acquisition Module
%
% USAGE DATA = EXAMPLE_DATA_ACQUISITION_CONTINUOUS(DEVICE_ID)
%
% Record demodulator sample data "continuously" (without triggering) using the a
% Software using the Data Acquisition Module from the device specified by
% DEVICE_ID, e.g., 'dev1000' or 'uhf-dev1000'. All acquired data is returned in
% DATA: Do not increase TOTAL_DURATION without removing this continuous save.
%
% USAGE DATA = EXAMPLE_DATA_ACQUISITION_CONTINUOUS(DEVICE_ID, 'FILENAME', FILENAME)
%
% Additionally save the data to file, see 'save/'
% parameters.
%
% NOTE This example does not perform any device configuration. If the streaming
% nodes corresponding to the signal_paths below are not enabled, no data will be
% recorded.
%
% NOTE Please ensure that the ziDAQ folders 'Driver' and 'Utils' are in your
% Matlab path. To do this (temporarily) for one Matlab session please navigate
% to the ziDAQ base folder containing the 'Driver', 'Examples' and 'Utils'
% subfolders and run the Matlab function ziAddPath().
% >>> ziAddPath;
%
% Use either of the commands:
% >>> help ziDAQ
% >>> doc ziDAQ
% in the Matlab command window to obtain help on all available ziDAQ commands.
%
% Copyright 2008-2018 Zurich Instruments AG


clear ziDAQ;

if ~exist('device_id', 'var')
    error(['No value for device_id specified. The first argument to the ' ...
           'example should be the device ID on which to run the example, ' ...
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

% The API level supported by this example.
supported_apilevel = 6;
% Create an API session; connect to the correct Data Server for the device.
[device, ~] = ziCreateAPISession(device_id, supported_apilevel);

ziApiServerVersionCheck();

branches = ziDAQ('listNodes', ['/' device ], 0);
if ~any(strcmpi([branches], 'DEMODS'))
  data = [];
  fprintf('\nThis example requires lock-in functionality which is not available on %s.\n', device);
  return
end

% Define parameters relevant to this example. Default values specified by the
% inputParser are overwritten if specified via `varargin`.
p = inputParser;
% The base filename to store data to, see 'save/filename'.
p.addParamValue('filename', '', @isstr);
p.parse(varargin{:});
filename = p.Results.filename;

% Enable ziDAQ's logging, see the Programming Manual for location of the log files.
ziDAQ('setDebugLevel', 0);

% Define a list of signal paths that we would like to record in the module.
demod_path = ['/' device '/demods/0/sample'];
signal_paths = {};
signal_paths{end+1} = [demod_path, '.x'];  % The demodulator X output.
signal_paths{end+1} = [demod_path, '.y'];  % The demodulator Y output.
% It's also possible to add signals from other node paths, for example:
% signal_paths{end+1} = ['/' device '/demods/1/sample', '.y'];

% This a helper look-up table to read the data corresponding to a signal path from the data returned by the Data
% Acquisition Module's read() function.
data_path_lookup = containers.Map();
data_path_lookup([demod_path, '_x']) = @(data) data.(device).demods(1).sample_x;
data_path_lookup([demod_path, '_y']) = @(data) data.(device).demods(1).sample_y;

% A helper look-up to store all the data returned.
data = containers.Map();
data([demod_path, '_x']) = {}; % Empty cell-array.
data([demod_path, '_y']) = {};

% Check the device has demodulator streaming nodes using the 'listNodes' function.
% In the following we bitwise-or the following flags: 1: recursive; 2: absolute; 16: streamingonly.
flags = bitor(1, 2);
flags = bitor(flags, 16);
streaming_nodes = ziDAQ('listNodes', ['/', device], flags);
if ~any(cellfun(@(x)~isempty(x), regexpi(num2str(demod_path), streaming_nodes)))
    message = ['Device ', device, ' does not have demodulators.\n', ...
               'Please modify the example to specify an available signal_path based\n', ...
               'on one or more of the following streaming nodes:\n'];
    for ii=1:length(streaming_nodes)
        message = [message, sprintf('%s\n', streaming_nodes{ii})];
    end
    fprintf(message);
    error('Demodulator streaming nodes unavailable - see the message above for more information.');
end

% Defined the total time we would like to record data for and its sampling rate.
total_duration = 5;  % Time in seconds: This examples stores all the acquired data in the `data` map - remove this
                     % continuous storing in read_data_update_plot before increasing total_duration!
module_sampling_rate = 30000; % Number of points/second
burst_duration = 0.2; % Time in seconds for each data burst/segment.
num_cols = ceil(module_sampling_rate*burst_duration);
num_bursts = ceil(total_duration/burst_duration);

% Create an instance of the Data Acquisition Module.
h = ziDAQ('dataAcquisitionModule');

% Configure the Data Acquisition Module.
% Set the device that will be used for the trigger - this parameter must be set.
ziDAQ('set', h, 'device', device);

% Specify continuous acquisition (type=0).
ziDAQ('set', h, 'type', 0);

% 'grid/mode' - Specify the interpolation method of
%   the returned data samples.
%
% 1 = Nearest. If the interval between samples on the grid does not match
%     the interval between samples sent from the device exactly, the nearest
%     sample (in time) is taken.
%
% 2 = Linear interpolation. If the interval between samples on the grid does
%     not match the interval between samples sent from the device exactly,
%     linear interpolation is performed between the two neighbouring
%     samples.
%
% 4 = Exact. The subscribed signal with the highest sampling rate (as sent
%     from the device) defines the interval between samples on the DAQ
%     Module's grid. If multiple signals are subscribed, these are
%     interpolated onto the grid (defined by the signal with the highest
%     rate, 'highest_rate'). In this mode, duration is
%     read-only and is defined as num_cols/highest_rate.
ziDAQ('set', h, 'grid/mode', 2);
% 'count' - Specify the number of bursts of data the
%   module should return (if endless=0). The
%   total duration of data returned by the module will be
%   count*duration.
ziDAQ('set', h, 'count', num_bursts);
% 'duration' - Burst duration in seconds.
%   If the data is interpolated linearly or using nearest neighbout, specify
%   the duration of each burst of data that is returned by the DAQ Module.
ziDAQ('set', h, 'duration', burst_duration);
% 'grid/cols' - The number of points within each duration.
%   This parameter specifies the number of points to return within each
%   burst (duration seconds worth of data) that is
%   returned by the DAQ Module.
ziDAQ('set', h, 'grid/cols', num_cols);

if ~strcmp(filename, '')
    % 'save/fileformat' - The file format to use for the saved data.
    %    0 - Matlab
    %    1 - CSV
    ziDAQ('set', h, 'save/fileformat', 1);
    % 'save/filename' - Each file will be saved to a
    % new directory in the Zurich Instruments user directory with the name
    % filename_NNN/filename_NNN/
    ziDAQ('set', h, 'save/filename', filename);
    % 'save/saveonread' - Automatically save the data
    % to file each time read() is called.
    ziDAQ('set', h, 'save/saveonread', 1);
end

for ii=1:length(signal_paths)
    fprintf('Subscribing to %s.\n', signal_paths{ii});
    ziDAQ('subscribe', h, signal_paths{ii});
end

clockbase = double(ziDAQ('getInt', ['/', device, '/clockbase']));

figure(1)
clf()
xlabel('Time (s)')
ylabel('Subscribed signals')
xlim([0, total_duration])
hold on;

ts0 = nan;
read_count = 0;

% Start recording data.
ziDAQ('execute', h);

% Record data in a loop with timeout.
timeout = 1.5*total_duration;
t0_measurement = tic;
% The maximum time to wait before reading out new data.
t_update = 0.9*burst_duration;
while ~ziDAQ('finished', h)
    t0_loop = tic;
    if toc(t0_measurement) > timeout
        ziDAQ('clear', h);
        error(['Timeout after ', num2str(timeout), 's - recording not complete. ',
               'Are the streaming nodes enabled? Has a valid signal_path been specified?']);
    end
    [data, ts0] = read_data_update_plot(h, data, ts0, clockbase, signal_paths, data_path_lookup);
    read_count = read_count + 1;
    % We don't need to update too quickly.
    pause(max(0, t_update - (toc(t0_loop))));
end
% There may be new data between the last read() and calling finished().
[data, ~] = read_data_update_plot(h, data, ts0, clockbase, signal_paths, data_path_lookup);

% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', h);

end

function [data, timestamp0] = read_data_update_plot(h, data, timestamp0, clockbase, signal_paths, data_path_lookup)
% READ_DATA_UPDATE_PLOT
%
% Read the acquired data out from the module and plot it.

data_read = ziDAQ('read', h);
progress = ziDAQ('progress', h);
ts0 = 0;
% Loop over all the subscribed signals:
for ii=1:length(signal_paths)
    % Replace e.g. '.x' with '_x'
    signal_path = strrep(signal_paths{ii}, '.', '_');
    if ziCheckPathInData(data_read, signal_path)
        f = data_path_lookup(signal_path);
        signal_bursts = f(data_read);
        % Loop over all the bursts for the subscribed signal. More than one burst may be returned at a time, in
        for n=1:length(signal_bursts)
            signal_burst = signal_bursts{n};
            if isnan(timestamp0)
                % Set our first timestamp to the first timestamp we obtain.
                timestamp0 = double(signal_burst.timestamp(1, 1));
            end
            num_samples = length(signal_burst.value);
            % Convert from device ticks to time in seconds.
            t = (double(signal_burst.timestamp(1, :)) - timestamp0)/clockbase;
            value = signal_burst.value(1, :);
            plot(t, value);
            dt = t(end) - t(1);
            fprintf('Progress: %.2f%%, Burst %d: %s contains %d samples spanning %.2f s.\n', 100*progress, n, signal_path, ...
                    num_samples, dt);
            % Append all bursts to our data variable.
            % NOTE: This should only be done for short recordings (small total_duration) to avoid high memory consumption!
            tmp = data(signal_path);
            tmp{end+1} = signal_burst;
            data(signal_path) = tmp;
        end
    end
    title(sprintf('Progress of data acquisition: %.2f%%.', 100*progress));
    pause(0.01)
end

end
