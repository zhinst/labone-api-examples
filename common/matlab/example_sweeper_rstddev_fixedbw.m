function data = example_sweeper_rstddev_fixedbw(device_id, varargin)
% EXAMPLE_SWEEPER_RSTDDEV_FIXEDBW Perform a frequency sweep plotting the stddev in demodulator output R using ziDAQ's sweep module
%
% USAGE DATA = EXAMPLE_SWEEPER_RSTDDEV_FIXEDBW(DEVICE_ID)
%
% Perform a frequency sweep using a fixed bandwidth for all frequencies and
% plot the standard deviation of a demodulator's magnitude. DEVICE_ID should
% be a string, e.g., 'dev1000' or 'uhf-dev1000'.
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
apilevel_example = 6;
% Create an API session; connect to the correct Data Server for the device.
[device, props] = ziCreateAPISession(device_id, apilevel_example);
ziApiServerVersionCheck();

branches = ziDAQ('listNodes', ['/' device ], 0);
if ~any(strcmpi([branches], 'DEMODS'))
  data = [];
  fprintf('\nThis example requires lock-in functionality which is not available on %s.\n', device);
  return
end

% Define parameters relevant to this example. Default values specified by the
% inputParser below are overwritten if specified as name-value pairs via the
% `varargin` input argument.
p = inputParser;
isnonnegscalar = @(x) isnumeric(x) && isscalar(x) && (x > 0);

% The value used for the Sweeper's 'samplecount' parameter: This
% specifies the number of points that will be swept (i.e., the number of
% frequencies swept in a frequency sweep).
p.addParamValue('sweep_samplecount', 100, isnonnegscalar);

% The signal output mixer amplitude, [V].
p.addParamValue('amplitude', 0.1, @isnumeric);

p.parse(varargin{:});

% Define some other helper parameters.
demod_c = '0'; % demod channel, for paths on the device
demod_idx = str2double(demod_c)+1; % 1-based indexing, to access the data
out_c = '0'; % signal output channel
% Get the value of the instrument's default Signal Output mixer channel.
out_mixer_c = num2str(ziGetDefaultSigoutMixerChannel(props, str2num(out_c)));
in_c = '0'; % signal input channel
osc_c = '0'; % oscillator

tc = 0.007; % [s]
demod_rate = 13e3;

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device);

% Configure the device ready for this experiment.
ziDAQ('setInt', ['/' device '/sigins/' in_c '/imp50'], 1);
ziDAQ('setInt', ['/' device '/sigins/' in_c '/ac'], 1);
ziDAQ('setDouble', ['/' device '/sigins/' in_c '/range'], 0.5);
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/on'], 0);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/range'], 1);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/*'], 0);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/amplitudes/' out_mixer_c], p.Results.amplitude);
ziDAQ('setDouble', ['/' device '/sigouts/' out_c '/enables/' out_mixer_c], 1);
if strfind(props.devicetype, 'HF2')
    ziDAQ('setInt', ['/' device '/sigins/' in_c '/diff'], 0);
    ziDAQ('setInt', ['/' device '/sigouts/' out_c '/add'], 0);
end
ziDAQ('setDouble', ['/' device '/demods/*/phaseshift'], 0);
ziDAQ('setInt', ['/' device '/demods/*/order'], 4);
ziDAQ('setDouble', ['/' device '/demods/' demod_c '/rate'], demod_rate);
ziDAQ('setInt', ['/' device '/demods/' demod_c '/harmonic'], 1);
ziDAQ('setInt', ['/' device '/demods/' demod_c '/enable'], 1);
ziDAQ('setInt', ['/' device '/demods/*/oscselect'], str2double(osc_c));
ziDAQ('setInt', ['/' device '/demods/*/adcselect'], str2double(in_c));
ziDAQ('setDouble', ['/' device '/demods/*/timeconstant'], tc);
ziDAQ('setDouble', ['/' device '/oscs/' osc_c '/freq'], 400e3); % [Hz]

%% Sweeper settings
% Create a thread for the sweeper
h = ziDAQ('sweep');
% Device on which sweeping will be performed
ziDAQ('set', h, 'device', device);
% Sweeping setting is the frequency of the output signal
ziDAQ('set', h, 'gridnode', ['oscs/' osc_c '/freq']);
% Start frequency = 1 kHz
ziDAQ('set', h, 'start', 1e3);
% Stop frequency
if strfind(props.devicetype, 'MF')
    stop = 500e3;
else
    stop = 10e6;
end
ziDAQ('set', h, 'stop', stop);
% sweep_samplecount measurement points (for sweep_samplecount different
% frequencies input signal Parameters will be recorded)
ziDAQ('set', h, 'samplecount', p.Results.sweep_samplecount);
% Single sweep
ziDAQ('set', h, 'loopcount', 1);
% Logarithmic sweep mode
ziDAQ('set', h, 'xmapping', 1);
% Binary scan type = 1
ziDAQ('set', h, 'scan', 0);
% We don't require a fixed settling/time since there is no DUT involved
% in this example's setup (only a simple feedback cable) so set this to
% zero. We need only wait for the filter response to settle, specified via
% settling/inaccuracy.
ziDAQ('set', h, 'settling/time', 0);
% The settling/inaccuracy' parameter defines the settling time the
% sweeper should wait before changing a sweep parameter and recording the next
% sweep data point. The settling time is calculated from the specified
% proportion of a step response function that should remain. The value
% provided here, 100m, is appropriate for fast and accurate amplitude
% measurements. For precise noise measurements it should be set to ~100n.
% Note: The actual time the sweeper waits before recording data is the maximum
% time specified by settling/time and defined by
% settling/inaccuracy.
ziDAQ('set', h, 'settling/inaccuracy', 0.0001);
% Minimum time to record and average data is 50 time constants.
ziDAQ('set', h, 'averaging/tc', 50);
% Minimal number of samples that we want to record and average is 1000.
% Note, the number of samples used for averaging will be the maximum number of
% samples specified by either averaging/tc or averaging/sample.
ziDAQ('set', h, 'averaging/sample', 1000);
% Use a fixed bandwidth for all frequencies (set 0 for 'auto')
ziDAQ('set', h, 'bandwidthcontrol', 1);
% Use a bandwidth of 100 Hz
ziDAQ('set', h, 'bandwidth', 100);
% Sets the bandwidth overlap mode (default 0). If enabled, the bandwidth of a
% sweep point may overlap with the frequency of neighboring sweep points. The
% effective bandwidth is only limited by the maximal bandwidth setting and
% omega suppression. As a result, the bandwidth is independent of the number
% of sweep points. For frequency response analysis bandwidth overlap should be
% enabled to achieve maximal sweep speed (default: 0). 0 = Disable, 1 = Enable.
ziDAQ('set', h, 'bandwidthoverlap', 0);


% Subscribe to the node from which data will be recorded
ziDAQ('subscribe', h, ['/' device '/demods/' demod_c '/sample']);

% Start sweeping
ziDAQ('execute', h);

frequencies = nan(1, p.Results.sweep_samplecount);
r = nan(1, p.Results.sweep_samplecount);
theta = nan(1, p.Results.sweep_samplecount);
data = [];

figure(1); clf;
timeout = 60;
t0 = tic;
% Read and plot intermediate data until the sweep has finished.
while ~ziDAQ('finished', h)
    pause(1);
    tmp = ziDAQ('read', h);
    fprintf('Sweep progress %0.0f%%\n', ziDAQ('progress', h) * 100);
    % Using intermediate reads we can plot a continuous refinement of the ongoing
    % measurement. If not required it can be removed.
    if ziCheckPathInData(tmp, ['/' device '/demods/' demod_c '/sample'])
        sample = tmp.(device).demods(demod_idx).sample{1};
        if ~isempty(sample)
            data = tmp;
            % Get the standard deviation of the magnitude and phase of demodulator from
            % the sweeper result.
            rstddev = sample.rstddev;
            theta = sample.phase;
            % Frequency values at which measurement points were taken
            frequencies = sample.grid;
            valid = ~isnan(frequencies);
            plot_data(frequencies(valid), rstddev(valid), theta(valid), p.Results.amplitude, '.-')
            drawnow;
        end
    end
    if toc(t0) > timeout
        ziDAQ('clear', h);
        error('Timeout: Sweeper failed to finish after %f seconds.', timeout)
    end
end
fprintf('Sweep completed after %.2f s.\n', toc(t0));

% now read the data. This command can also be executed during the waiting.
tmp = ziDAQ('read', h);

% unsubscribe from the node; stop filling the data from that node to the
% internal buffer in the server
ziDAQ('unsubscribe', h, ['/' device '/demods/*/sample']);

% Process any remainging data returned by read().
if ziCheckPathInData(tmp, ['/' device '/demods/' demod_c '/sample'])
    sample = tmp.(device).demods(demod_idx).sample{1};
    if ~isempty(sample)
        data = tmp;
        % Get the standard deviation of the magnitude and phase of demodulator from
        % the sweeper result.
        rstddev = sample.rstddev;
        theta = sample.phase;
        % Frequency values at which measurement points were taken
        frequencies = sample.grid;
        % Plot the final result
        plot_data(frequencies, rstddev, theta, p.Results.amplitude, '-')
    end
end

% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', h);

end


function plot_data(frequencies, y, theta, amplitude, style)
% Plot data
clf
subplot(2, 1, 1)
s = semilogx(frequencies, y, style);
set(s, 'LineWidth', 1.5)
set(s, 'Color', 'black');
grid on
xlabel('Frequency [Hz]')
ylabel('R, Standard Deviation [V]')
subplot(2, 1, 2)
s = semilogx(frequencies, theta*180/pi, style);
set(s, 'LineWidth', 1.5)
set(s, 'Color', 'black');
grid on
xlabel('Frequency [Hz]')
ylabel('Phase [deg]')
end
