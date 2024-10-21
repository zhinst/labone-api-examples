%% Description -----------------------------------------------------------
% Copyright 2023 Zurich Instruments AG
% This example demonstrates how to obtain a Bode plot using the Sweeper 
% module for the SHFLI Lock-in Amplifier.

% Clear and close everything
close all; clear; clc;

%% User settings ---------------------------------------------------------

% Serial number of instrument in its rear panel.
device = 'dev10000';

% Interface between the instrument and the host computer: '1GbE'
interface = '1GbE';

% IP address of LabOne data server host, e.g., 'localhost' or '169.254.1.2'
host = 'localhost';

% Sweep parameters
start_frequency = 100e6;        % [Hz]
stop_frequency = 8400e6;        % [Hz]
num_points = 50;                % Number of frequency points 

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
    % Adjust the data rate of demodulator 1
    ['/' device '/demods/0/rate'], 10e3
    % Enable continuous data streaming of demodulator 1
    ['/' device '/demods/0/trigger/triggeracq'], 0
    % Enable the data transfer from demodulator 1 to data server
    ['/' device '/demods/0/enable'], 1
};

% Apply all the settings to the device via a transaction
ziDAQ('set', device_settings);

%% Sweeper module --------------------------------------------------------

% Create an instance of the Sweeper Module
sweeper = ziDAQ('sweep');

% Assign the instrument to the sweeper object (must be set first)
ziDAQ('set', sweeper, 'device', device);

% Specify that a multiband sweep of the specified channel and oscillator should be performed
ziDAQ('set', sweeper, 'gridnode', ['/' device '/multiband/sigins0/oscs0']);

% Set the start and stop values of the sweeping parameter
ziDAQ('set', sweeper, 'start', start_frequency);
ziDAQ('set', sweeper, 'stop', stop_frequency);

% Set the number of points in the sweep range
ziDAQ('set', sweeper, 'samplecount', num_points);

% Sequential sweep from start to stop points
ziDAQ('set', sweeper, 'scan', 'sequential');

% Linear scale of sweeping parameter (frequency)
ziDAQ('set', sweeper, 'xmapping', 'linear');

% Automatic control of demodulation bandwidth
ziDAQ('set', sweeper, 'bandwidthcontrol', 2);

% Demodulation filter order
ziDAQ('set', sweeper, 'order', 3);

% Maximum measurement bandwidth [Hz]
ziDAQ('set', sweeper, 'maxbandwidth', 4.0e3);

% Single-sweep mode
ziDAQ('set', sweeper, 'endless', 0);

%% Subscription to signal path -------------------------------------------

% Subscribe to the signal path of demodulator 1 for acquisition
path = ['/' device '/demods/0/sample'];
ziDAQ('subscribe', sweeper, path);

%% Run sweeper -----------------------------------------------------------

fprintf('\nStart sweeping frequency...\n\n');

% Start the sweep
ziDAQ('execute', sweeper);

sweep_completed = true;
timeout = 30;
t0 = tic;
%while ziDAQ('progress', sweeper) < 1.0 && ~ziDAQ('finished', sweeper)
while ~ziDAQ('finished', sweeper)
   pause(1);
   fprintf('Progress %0.0f%%\n', ziDAQ('progress', sweeper) * 100);
   if toc(t0) > timeout
       sweep_completed = false;
       break;
   end 
end
ziDAQ('finish', sweeper);
ziDAQ('unsubscribe', sweeper, '*');

if sweep_completed
    fprintf('\nSweeper finished within %.1f s.\n\n', toc(t0));
else
    fprintf('\nTimeout: Sweeper could not finish within %.1f s.\n\n', timeout);
end

% Read out the data acquired by the sweeper
data = ziDAQ('read', sweeper);

% Destroy the sweeper object
ziDAQ('clear', sweeper);

%% Disconnection ---------------------------------------------------------

% Disconnect the device from data server
% ziDAQ('disconnectDevice', device);

% Destroy the API session
clear ziDAQ

%% Plotting --------------------------------------------------------------

if sweep_completed
    
    % Extract signal frequency, amplitude and phase
    sample = data.(device).demods(1).sample{1,1};
    freq = sample.grid;
    amp = sample.r;
    phase = sample.phase;

    % Visualization
    figure('Name','Bode','NumberTitle','on');
    set(gca,'FontSize',12,'LineWidth',2,'Color',[1 1 1],'Box','on');
    subplot(2,1,1)
    h = plot(freq * 1e-9, amp);
    set(h,'LineWidth',1,'LineStyle','-','Color',[0 0.4470 0.7410])
    xlabel('Frequency  (GHz)','fontsize',10,'fontweight','n','color','k');
    ylabel('Amplitude  (V)','fontsize',10,'fontweight','n','color','k');
    xlim([start_frequency stop_frequency] * 1e-9);
    grid on
    title('Frequency Response: Amplitude and Phase')
    subplot(2,1,2)
    h = plot(freq * 1e-9, (180/pi)*phase);
    set(h,'LineWidth',1 ,'LineStyle','-','Color',[0.6350 0.0780 0.1840])
    xlabel('Frequency  (GHz)','fontsize',10,'fontweight','n','color','k');
    ylabel('Phase  (deg)','fontsize',10,'fontweight','n','color','k');
    xlim([start_frequency stop_frequency] * 1e-9);
    grid on

end
% ------------------------------------------------------------------------
