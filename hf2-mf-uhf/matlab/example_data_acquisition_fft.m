function data = example_data_acquisition_fft(device_id, varargin)
% EXAMPLE_DATA_ACQUISITION_FFT Perform an FFT using ziDAQ's Data Acquisition module
%
% USAGE DATA = EXAMPLE_DATA_ACQUISITION_FFT(DEVICE_ID)
%
% The following example demonstrates how to use ziDAQ's Data Acquisition Module
% for capturing FFTs. DEVICE_ID should be a string, e.g., 'dev1000' or 'uhf-dev1000'.
%
% NOTE Additional configuration: Connect signal output 1 to signal input 1
% with a BNC cable.
%
% NOTE This is intended to be a simple example demonstrating how to connect
% to a Zurich Instruments device from MATLAB.
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

% The value used for the dataAcquisitionModule Module's 'bit' parameter: This
% specifies the frequency resolution of the FFT; the number of bins in the
% FFT spectrum is 2^bits.
p.addParamValue('dataAcquisitionModule_bit', 16, isnonnegscalar);

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

time_constant = 8e-5; % [s]
demod_rate = 10e3;

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device);

%% Configure the device ready for this experiment.
ziDAQ('setInt', ['/' device '/sigins/' in_c '/imp50'], 1);
ziDAQ('setInt', ['/' device '/sigins/' in_c '/ac'], 1);
ziDAQ('setDouble', ['/' device '/sigins/' in_c '/range'], 2);
ziDAQ('setInt', ['/' device '/sigouts/' out_c '/on'], 1);
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
ziDAQ('setDouble', ['/' device '/demods/*/timeconstant'], time_constant);
ziDAQ('setDouble', ['/' device '/oscs/' osc_c '/freq'], 400e3); % [Hz]

% Wait for the demodulator filter to settle
pause(10*time_constant);

%% dataAcquisitionModule settings
% Create a thread for the dataAcquisitionModule
h = ziDAQ('dataAcquisitionModule');
% Device on which dataAcquisitionModule will be performed
ziDAQ('set', h, 'device', device);
% Set exact grid mode. This is the most suitable mode for FFTs
ziDAQ('set', h, 'grid/mode', 4);
% Number of bins =  2^bits
ziDAQ('set', h, 'grid/cols', 2^p.Results.dataAcquisitionModule_bit);
% Select standard FFT(x + iy)
% Subscribe to the node from which data will be recorded
demod_path = ['/' device '/demods/' demod_c '/sample.xiy.fft.abs'];
% The dots in the signal paths are replaced by underscores in the data returned by MATLAB to
% prevent conflicts with the MATLAB syntax.
demod_path_us = ['/' device '/demods/' demod_c '/sample_xiy_fft_abs'];
filter_path = ['/' device '/demods/' demod_c '/sample.xiy.fft.abs.filter'];
filter_path_us = ['/' device '/demods/' demod_c '/sample_xiy_fft_abs_filter'];
ziDAQ('subscribe', h, demod_path);
ziDAQ('subscribe', h, filter_path);
ziDAQ('set', h, 'triggernode', ['/' device '/demods/' demod_c '/sample.r']);
% The module to return preview. This is useful to display the progress of high resolution FFTs
% that take a long time to capture. Successively higher resolution FFTs are calculated and returned.
ziDAQ('set', h, 'preview', 1);

% Enable the dataAcquisitionModule's module.
ziDAQ('set', h, 'enable', 1);
% Force a trigger to start the data acquisition. A wait is necessary between starting and
% forcing the trigger. Otherwise no data is returned.
buffer_size = ziDAQ('getDouble', h, 'buffersize');
pause(buffer_size * 2.0);
ziDAQ('set', h, 'forcetrigger', 1);

data = [];

figure(1); clf;
timeout = 60;
t0 = tic;
% Read and plot intermediate data until the dataAcquisitionModule has finished.
while ~ziDAQ('finished', h)
    pause(0.5);
    tmp = ziDAQ('read', h);
    data = tmp;
    fprintf('dataAcquisitionModule progress %0.0f%%\n', ziDAQ('progress', h) * 100)
    % Using intermediate reads we can plot a continuous refinement of the ongoing
    % measurement. If not required it can be removed.
    assemble_and_plot_data(tmp);
    if toc(t0) > timeout
       ziDAQ('clear', h);
       error('Timeout: dataAcquisitionModule failed to finish after %f seconds.', timeout)
    end
end

% Read and process any remaining data returned by read().
tmp = ziDAQ('read', h);
data = tmp;

% unsubscribe from the nodes; stop filling the data from that node to the
% internal buffer in the server
ziDAQ('unsubscribe', h, filter_path);
ziDAQ('unsubscribe', h, demod_path);

assemble_and_plot_data(tmp);

function assemble_and_plot_data(tmp)
    if ziCheckPathInData(tmp, demod_path_us)
        sample = tmp.(device).demods(demod_idx).sample_xiy_fft_abs{1};
        if ~isempty(sample)
            % Get the FFT of the demodulator's magnitude from the dataAcquisitionModule's result.
            r = sample.value;
            filter_data = tmp.(device).demods(demod_idx).sample_xiy_fft_abs_filter{1};
            % Frequency data is calculated from the grid column delta.
            bin_resolution = filter_data.header.gridcoldelta;
            bandwidth = bin_resolution * length(r);
            % Plot only the non-NaN values in the data (the lower resolution previews sparsely
            % populate the full-resolution data chunk).
            valid = ~isnan(r);
            valid_data_points = nnz(valid==1);
            if (valid_data_points > 0)
                frequencies = linspace(-(bandwidth/2.0), bandwidth/2.0, length(valid));
                fprintf('Number of bins: %d.\n', valid_data_points);
                plot_data(frequencies(valid), r(valid), filter_data.value(valid), p.Results.amplitude, '.-b');
                drawnow;
            end
        end
    end
end

% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', h);

end

function plot_data(frequencies, r, filter_data, sigout_amplitude, style)
% Plot data
clf
subplot(2, 1, 1)
% Plot the uncompensated data from the demodulator.
s = plot(frequencies, 20*log10(r*2*sqrt(2)/sigout_amplitude), style);
set(s, 'LineWidth', 1)
set(s, 'Color', 'blue');
grid on
xlabel('Frequency [Hz]')
ylabel('Amplitude [dBV]')
subplot(2, 1, 2)
% Apply the filter compensation (filta_data) to the demod data and plot the result.
s = plot(frequencies, 20*log10((r./filter_data)*2*sqrt(2)/sigout_amplitude), style);
set(s, 'LineWidth', 1)
set(s, 'Color', 'blue');
grid on
xlabel('Frequency [Hz]')
ylabel('Amplitude [dBV] scaled with Filter')

end
