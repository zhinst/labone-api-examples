function [data, config] = example_data_acquisition_edge(device_id, varargin)
% EXAMPLE_DATA_ACQUISITION_EDGE Record triggered demod data using the Data Acquisition Module
%
% NOTE This example can only be ran on UHF and HF2 Instruments with
% the MF Option and MF Instruments with the MD Option enabled. The MF
% Option is not required to use the Data Acquisition Module. However,
% this example is a stand-alone example that generates (by creating a
% beat in demodulator data) and captures it's own triggers. As such,
% it requires a simple feedback BNC cable between Signal Output 0 and
% Signal Input 0 of the device.
%
% USAGE DATA = EXAMPLE_DATA_ACQUISITION_EDGE(DEVICE_ID)
%
% Record bursts of demodulator sample data using a software trigger
% from ziDAQ's 'Data Acquisition Module' module from the device specified by DEVICE_ID,
% e.g., 'dev1000' or 'uhf-dev1000'.
%
% The data acquisition module implements software triggering
% analogously to the types of triggering found in spectroscopes.
%
% This example generates a 'beat' in the demodulator signal in order to
% simulate 'events' in the demodulator data. Signal segments of these events
% are then recorded when the rising edge of the demodulator R value exceeds a
% certain threshold.
%
% NOTE Additional configuration: Connect signal output 1 to signal input 1
% with a BNC cable.
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
% This example runs on any device type but requires either the Multifrequency
% or Multidemodulator option.
required_devtype = '.*';
required_options = {'MF|MFK|MD'};
required_err_msg = ['This example requires either an HF2/UHF Instrument ' ...
                    'with the Multifrequency (MF) Option installed or an MF ' ...
                    'Instrument with Multidemodulator (MD) option installed. ' ...
                    'Note: The MF/MD Option is not a requirement to use the ' ...
                    'Data Acquisition module itself, just to run this example.'];
% Create an API session; connect to the correct Data Server for the device.
[device, props] = ziCreateAPISession(device_id, supported_apilevel, ...
                                     'required_devtype', '.*', ...
                                     'required_options', required_options, ...
                                     'required_err_msg', required_err_msg);
ziApiServerVersionCheck();

branches = ziDAQ('listNodes', ['/' device ], 0);
if ~any(strcmpi([branches], 'DEMODS'))
  data = []; config = [];
  fprintf('\nThis example requires lock-in functionality which is not available on %s.\n', device);
  return
end

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
isnonnegvector = @(x) isnumeric(x) && isvector(x) && all(x > 0);
% The indices of the demodulators to record for the experiment, 1-based
% indexing.
p.addParamValue('demod_idx', [1, 2], isnonnegvector);
% Pick a suitable (although conservative) demodulator rate based on the device
% class.
if strfind(props.devicetype, 'UHF')
    default_demod_rate = 100e3;
else
    default_demod_rate = 56e3;
end
p.addParamValue('demod_rate', default_demod_rate, isnonnegscalar);
p.addParamValue('event_frequency', 100, isnonnegscalar);
p.addParamValue('trigger_count', 1000, isnonnegscalar);
p.parse(varargin{:});
demod_rate = p.Results.demod_rate;
demod_idx = p.Results.demod_idx;
event_frequency = p.Results.event_frequency;
trigger_count = p.Results.trigger_count;

% More parameters relevant to this example, some of which we derive from the
% inputParser parameters. We package them in a struct for convenience.
config = struct();

% The value later used for the SW Trigger's 'duration' parameter:
% This is the duration in seconds of signal segment to record: Let's record
% half the duration of each beat.
config.trigger_duration = 0.5/event_frequency;  % [s]

% The value later used for the SW Trigger's 'delay' parameter: This
% specifies the delay in seconds to wait before recording the signal after the
% point in the time when the trigger is activated. A negative value indicates
% a pretrigger time.
config.trigger_delay = -0.125/event_frequency;  % [s]

% Signal output mixer amplitude, [V]. The trigger threshold must be based on
% this.
amplitude = 0.100;

% The value later used for the SW Trigger's 'level' parameter: This
% specifieds threshold level required to trigger an event.
config.trigger_level = 0.45*amplitude/sqrt(2.);

fprintf('Event frequency (beat freqency): %.1f\n', event_frequency);

% Define some other helper parameters.
config.demod_idx = demod_idx;
config.device = device;
config.clockbase = double(ziDAQ('getInt', ['/' device '/clockbase']));

% demod_idx is used to access the data in Matlab arrays and are therefore
% 1-based indexed. Node paths on the HF2/UHF use 0-based indexing.
config.demod_c = zeros(size(demod_idx));
for ii=demod_idx
    config.demod_c(ii) = num2str(demod_idx(ii)-1, '%0d');
end

out_c = '0';
in_c = '0';

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device);

%% Configure the device ready for this experiment.
ziDAQ('setInt', ['/' device '/sigins/' in_c '/imp50'], 1);
ziDAQ('setInt', ['/' device '/sigins/' in_c '/ac'], 0);
ziDAQ('setDouble', ['/' device '/sigins/' in_c '/range'], 2);
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/on'], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/range'], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/*'], 0);
if strfind(props.devicetype, 'HF2')
    ziDAQ('setInt', ['/' device '/sigins/' in_c '/diff'], 0);
    ziDAQ('setInt', ['/' device '/sigouts/' out_c '/add'], 0);
end
ziDAQ('setDouble', ['/' device '/demods/*/phaseshift'], 0);
for d=config.demod_c
    ziDAQ('setDouble', ['/' device '/demods/' d '/rate'], demod_rate);
end
% Ensure the configuration has taken effect before reading back the value actually set.
ziDAQ('sync');
demod_rate_set = ziDAQ('getDouble', ['/' device '/demods/' config.demod_c(1) '/rate']);

ziDAQ('setInt', ['/' device '/demods/*/harmonic'], 1);
for d=config.demod_c
    ziDAQ('setInt', ['/' device '/demods/' d '/enable'], 1);
end
ziDAQ('setInt', ['/' device '/demods/*/adcselect'], str2double(in_c));
ziDAQ('setInt', ['/' device '/demods/*/oscselect'], 0);

% Generate the beat.
ziDAQ('setInt', ['/' device '/demods/0/oscselect'], 0);
ziDAQ('setInt', ['/' device '/demods/1/oscselect'], 1);  % requires MF option.
ziDAQ('setDouble', ['/' device '/oscs/*/freq'], 400e3);  % [Hz]
ziDAQ('setDouble', ['/' device '/oscs/1/freq'], 400e3 + event_frequency);  % [Hz]
% We require 2 Signal Output mixer channels to superimpose the two signals
% with different frequencies in order to generate the beat.
out_mixer_c_0 = ziGetDefaultSigoutMixerChannel(props, 0);
out_mixer_c_1 = out_mixer_c_0 + 1;
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/' out_mixer_c_0], amplitude);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/' out_mixer_c_1], amplitude);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/enables/' out_mixer_c_0], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/enables/' out_mixer_c_1], 1);
order = 4;
ziDAQ('setInt', ['/' device '/demods/*/order'], order);
% A small timeconstant is required to see the interference between the
% demodulators
timeconstant = ziBW2TC(demod_rate_set/2, order);
ziDAQ('setDouble', ['/' device '/demods/0/timeconstant'], timeconstant);
timeconstant = ziBW2TC(10e3, order);
ziDAQ('setDouble', ['/' device '/demods/1/timeconstant'], timeconstant);
timeconstant = ziBW2TC(event_frequency, order);
ziDAQ('setDouble', ['/' device '/demods/2/timeconstant'], timeconstant);
for i=1:length(config.demod_c)
    timeconstants_set(i) = ziDAQ('getDouble', ['/' device '/demods/' config.demod_c(i) '/timeconstant']);
end

% Unsubscribe from any streaming data
ziDAQ('unsubscribe', '*');
% Flush all the buffers.
ziDAQ('sync');

% Wait for the demodulator filter to settle
pause(20*max(timeconstants_set));

% Create a Data Acquisition Module instance, the return argument is a handle to the module.
h = ziDAQ('dataAcquisitionModule');

%% Configure the Data Acquisition Module
% Device on which trigger will be performed
ziDAQ('set', h, 'device', device)
% The number of triggers to capture (if not running in endless mode).
ziDAQ('set', h, 'count', trigger_count);
ziDAQ('set', h, 'endless', 0);
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
%     rate, "highest_rate"). In this mode, duration is
%     read-only and is defined as num_cols/highest_rate.
%     demod samples.
grid_mode = 4;
ziDAQ('set', h, 'grid/mode', grid_mode);
%   type:
%     NO_TRIGGER = 0
%     EDGE_TRIGGER = 1
%     DIGITAL_TRIGGER = 2
%     PULSE_TRIGGER = 3
%     TRACKING_TRIGGER = 4
%     HW_TRIGGER = 6
%     TRACKING_PULSE_TRIGGER = 7
%     EVENT_COUNT_TRIGGER = 8
ziDAQ('set', h, 'type', 1);
%   triggernode, specify the triggernode to trigger on.
%     SAMPLE.X = Demodulator X value
%     SAMPLE.Y = Demodulator Y value
%     SAMPLE.R = Demodulator Magnitude
%     SAMPLE.THETA = Demodulator Phase
%     SAMPLE.AUXIN0 = Auxilliary input 1 value
%     SAMPLE.AUXIN1 = Auxilliary input 2 value
%     SAMPLE.DIO = Digital I/O value
triggernode = ['/' device '/demods/' config.demod_c(1) '/sample.r'];
ziDAQ('set', h, 'triggernode', triggernode);
%   edge:
%     POS_EDGE = 1
%     NEG_EDGE = 2
%     BOTH_EDGE = 3
ziDAQ('set', h, 'edge', 1)
demod_rate = ziDAQ('getDouble', ['/' device '/demods/' config.demod_c(1) '/rate']);
if grid_mode == 4
    % Exact mode: To preserve our desired trigger duration, we have to set
    % the number of grid columns to exactly match.
    sample_count = demod_rate*config.trigger_duration;  % [s]
    ziDAQ('set', h, 'grid/cols', sample_count);
else
    sample_count = 1024
    ziDAQ('set', h, 'grid/cols', sample_count);
    ziDAQ('set', h, 'duration', config.trigger_duration);
end
% The length of each trigger to record (in seconds).
% ziDAQ('set', h, 'duration', config.trigger_duration);
ziDAQ('set', h, 'delay', config.trigger_delay);
% Do not return overlapped trigger events.
ziDAQ('set', h, 'holdoff/time', config.trigger_duration);
ziDAQ('set', h, 'holdoff/count', 0);
ziDAQ('set', h, 'level', config.trigger_level)
% The hysterisis is effectively a second criteria (if non-zero) for triggering
% and makes triggering more robust in noisy signals. When the trigger `level`
% is violated, then the signal must return beneath (for positive trigger edge)
% the hysteresis value in order to trigger.
ziDAQ('set', h, 'hysteresis', 0.1*config.trigger_level)

% Unrequired parameters when type is EDGE_TRIGGER:
% ziDAQ('set', h, 'bitmask', 1);
% ziDAQ('set', h, 'bits', 1);

%% Subscribe to the demodulators
% fliplr: Subscribe in descending order so that we subscribe to the trigger
% demodulator last (demod 0). This way we will not start acquiring data on the
% trigger demod before we subscribe to other demodulators.
for d=fliplr(config.demod_c)
    ziDAQ('subscribe', h, ['/' device '/demods/' d '/sample.r']);
end

% Prepare a figure for plotting
figure(1); clf;
box on; grid on; hold on;
xlabel('\bf Time (relative to trigger position) [s]');
ylabel('\bf Signal');

fprintf('Num samples per signal segment: %d\n', sample_count);

%% Start recording
% now start the thread -> ready to be triggered
ziDAQ('execute', h);

timeout = 20; % [s]
num_triggers = 0;
n = 0;
t0 = tic;
tRead = tic;
dt_read = 0.250;
while ~ziDAQ('finished', h)
    pause(0.05);
    % Perform an intermediate readout of the data. the data between reads is
    % not acculmulated in the module - it is cleared, so that the next time
    % you do a read you (should) only get the triggers that came in between the
    % two reads.
    if toc(tRead) > dt_read
        data = ziDAQ('read', h);
        fprintf('Performed an intermediate read() of acquired data (time since last read %.3f s).\n', toc(tRead));
        fprintf('Data Acquisition Module progress (acquired %d of total %d triggers): %.1f%%\n', num_triggers, trigger_count, 100*ziDAQ('progress', h));
        tRead = tic;
        if ziCheckPathInData(data, ['/' device '/demods/' config.demod_c(1) '/sample_r'])
            num_triggers = num_triggers + check_data(data, config);
            % Do some other processing and save data...
            % ...
        end
    end
    % Timeout check
    if toc(t0) > timeout
        % If for some reason we're not obtaining triggers quickly enough, the
        % following command will force the end of the recording.
        if num_triggers == 0
            ziDAQ('finish', h);
            ziDAQ('clear', h);
            error('Failed to acquire any triggers before timeout (%d seconds). Missing feedback cable between sigout 0 and sigin 0?', timeout);
        else
            fprintf('Acquired %d triggers. Loop timeout (%.2f s) before acquiring %d triggers\n');
            fprintf('Increase loop `timeout` to acquire more.\n', num_triggers, timeout, trigger_count);
        end
    end
end
tEnd = toc(t0);

ziDAQ('unsubscribe', h, ['/' device '/demods/*/sample.r']);

% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', h);

end

function num_triggers = check_data(data, config)
%CHECK_DATA check data for sampleloss and plot some triggers for feedback

device = config.device;
demod_idx = config.demod_idx;

% We use cell arrays to address the individual segments from each trigger
num_triggers = length(data.(device).demods(demod_idx(1)).sample_r);
if num_triggers == 0
    return
end
fprintf('Data contains %d data segments (triggers).\n', num_triggers);
sampleloss = check_segments_for_sampleloss(data, config);
if any(sampleloss)
    fprintf('Warning: Sampleloss detected in %d triggers.\n', sum(sampleloss));
    if sum(sampleloss) == num_triggers
        fprintf('Error all triggers contained sampleloss.\n');
        num_triggers = 0;
        return
    end
else
    fprintf('No sampleloss detected.\n');
end

figure(1); cla;
plot_style = {'r-', 'b-', 'g-', 'k-'};
num_triggers_plotted = 0;
for i=1:num_triggers
    if num_triggers_plotted >= 100;
        % Only plot first 100 valid triggers.
        break;
    end
    if sampleloss(i)
        continue
    end
    for d=1:length(config.demod_c)
        % Convert the trigger timestamp to seconds. The trigger timestamp is
        % the timestamp at which the trigger criteria was fulfilled and has in
        % general a higher resolution than the demodulator rate.
        t_trigger = double(data.(device).demods(demod_idx(d)).sample_r{i}.header.createdtimestamp) - double(data.(device).demods(demod_idx(d)).sample_r{i}.header.gridcoloffset)*config.clockbase;
        t = (double(data.(device).demods(demod_idx(d)).sample_r{i}.timestamp) - t_trigger)/config.clockbase;
        R = data.(device).demods(demod_idx(d)).sample_r{i}.value;
        % Plot the signal segment, aligned using the trigger time.
        s(d) = plot(t, R, plot_style{d});
        set(s(d), 'LineWidth', 1.2);
    end
    num_triggers_plotted = num_triggers_plotted + 1;
end
plot(get(gca, 'xlim'), [config.trigger_level, config.trigger_level], '--k');
plot([0.0, 0.0], get(gca, 'ylim'), '--k');

num_demods = length(config.demod_c);
title(sprintf('\\bf %d signal segments from %d demodulators', num_triggers_plotted, num_demods))

end


function sampleloss = check_segments_for_sampleloss(data, config)
num_triggers = length(data.(config.device).demods(config.demod_idx(1)).sample_r);
sampleloss = logical(zeros(1, num_triggers));
for i=1:num_triggers
    for d=config.demod_idx
        % Check if any data is invalid. Unfortunately, sampleloss indicators not
        % implemented on software trigger yet.
        if any(isnan(data.(config.device).demods(config.demod_idx(d)).sample_r{i}.value))
            sampleloss(i) = (1 | sampleloss(i));
        end
        if isempty(data.(config.device).demods(config.demod_idx(d)).sample_r{i}.timestamp)
            sampleloss(i) = (1 | sampleloss(i));
        end
    end
end
end
