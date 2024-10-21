%% Description -----------------------------------------------------------
% Copyright 2024 Zurich Instruments AG
% This example demonstrates how to acquire triggered demodulator data using 
% the DAQ module for the SHFLI Lock-in Amplifier.

% Clear and close everything
close all; clear; clc;

%% User settings ---------------------------------------------------------

% Serial number of instrument in its rear panel.
device = 'dev10000';

% Interface between the instrument and the host computer: '1GbE'
interface = '1GbE';

% IP address of LabOne data server host, e.g., 'localhost' or '169.254.1.2'
host = 'localhost';

% Number of samples to be measured following a trigger event
burst_length = 256;

% Number of triggers to be issued
trigger_count = 3;

%% Connection to instrument ----------------------------------------------

% Close current API sessions
clear ziDAQ

% Create an API session to the data server
port = 8004;        % Data server port to communicate
api_level = 6;      % Maximum API level supported by the instrument
ziDAQ('connect', host, port, api_level);

% Establish a connection between data server and instrument
ziDAQ('connectDevice', device, interface);

%% Instrument settings ---------------------------------------------------

% Define all the settings in a cell
device_settings = {
    % Use software enabled trigger acquisition for the example
    ['/' device '/demods/0/trigger/source'], 1024
    % Adjust the data rate of demodulator 1
    ['/' device '/demods/0/rate'], 2048
    % Set the number of samples to be measured following a trigger event
    ['/' device '/demods/0/burstlen'], burst_length
    % Enable the triggered data acquisition of demodulator 1
    ['/' device '/demods/0/trigger/triggeracq'], 1
    % Enable data transfer from demodulator 1 to data server
    ['/' device '/demods/0/enable'], 1
};

% Apply all the settings to the device via a transaction
ziDAQ('set', device_settings);

% Time difference (s) between two consecutive timestamp ticks
dt_device = ziDAQ('getDouble', ['/' device '/system/properties/timebase']);

%% DAQ module --------------------------------------------------------

% Create an instance of the DAQ Module
daq_module = ziDAQ('dataAcquisitionModule');

% Set the device that will be used for the trigger - this parameter must be set.
ziDAQ('set', daq_module, 'device', device);

% Configure the daq module to look out for bursts coming from the device (triggering is handled by the device)
ziDAQ('set', daq_module, 'type', 'burst_trigger');

% No offset for the trigger position
ziDAQ('set', daq_module, 'delay', 0.0);

% Set grid mode to be 'exact' or 4, meaning no interpolation from the daq module
ziDAQ('set', daq_module, 'grid/mode', 'exact');

% Set the grid columns to be equal to the burst length, given that the grid/mode is exact
ziDAQ('set', daq_module, 'grid/cols', burst_length);

% Set the number of expected triggers to be acquired
ziDAQ('set', daq_module, 'count', trigger_count);

% Set the DAQ module to trigger on a change of trigger index, i.e. on HW triggers.
ziDAQ('set', daq_module, 'triggernode', ['/' device '/demods/0/sample.trigindex']);

%% Subscription to signal path -------------------------------------------

trigger_signal_path = ['/' device '/demods/0/sample.r'];
ziDAQ('subscribe', daq_module, trigger_signal_path);

%% Run DAQ module --------------------------------------------------------

fprintf('\nStart DAQ module ...\n\n');

ziDAQ('execute', daq_module);

% Start the triggering process
for i = 1:1:trigger_count
    % Issue the software trigger
    ziDAQ('setInt', ['/' device '/system/swtriggers/0/single'], 1);
    fprintf('Trigger no.%i was sent!\n', i);
    % Wait 1 second before triggering again
    pause(1);
end
fprintf('\n');

daq_completed = true;
timeout = 60;
t0 = tic;
while ziDAQ('progress', daq_module) < 1.0 && ~ziDAQ('finished', daq_module)
    pause(1);
    fprintf('Progress %0.0f%%\n', ziDAQ('progress', daq_module) * 100);
    if toc(t0) > timeout
        daq_completed = false;
    end
end
ziDAQ('finish', daq_module);
ziDAQ('unsubscribe', daq_module, '*');

if daq_completed
    fprintf('\nDAQ module finished within %.1f s.\n\n', toc(t0));
else
    fprintf('\nTimeout: DAQ module could not finish within %.1f s.\n\n', timeout);
end

% Read out the data acquired by the daq module
data = ziDAQ('read', daq_module);

% Destroy the daq module object
ziDAQ('clear', daq_module);

%% Disconnection ---------------------------------------------------------

% Disconnect the device from data server
% ziDAQ('disconnectDevice', device);

% Destroy the API session
clear ziDAQ

%% Plotting --------------------------------------------------------------

if daq_completed
    all_samples = data.(device).demods(1).sample_r;
    figure('Name','DAQ Trigger Data','NumberTitle','on');
    set(gca,'FontSize',12,'LineWidth',2,'Color',[1 1 1],'Box','on');
    for i=1:1:size(all_samples, 2)
        sample = all_samples{1, i};
        values = sample.value * 1e6;
        timestamps = double(sample.timestamp - sample.timestamp(1,1)) * dt_device;
        subplot(size(all_samples, 2), 1, i);
        h = plot(timestamps, values);
        set(h,'LineWidth',1,'LineStyle','-');
        xlabel('Time (sec)','fontsize',10,'fontweight','n','color','k');
        ylabel('Signal (μV)','fontsize',10,'fontweight','n','color','k');
    end
end
% ------------------------------------------------------------------------
