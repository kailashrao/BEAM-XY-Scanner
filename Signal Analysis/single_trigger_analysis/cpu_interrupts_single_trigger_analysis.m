% cpu_interrupts_single_trigger_analysis.m (latency_single_edge.m)
% Updated 6/4/2026 by Kailash Rao

% Works for T0002-T0005 (CPU Interrupts)

% CPU Interrupts take significant time to execute compared to the oscilloscope's current resolution of 1.6us
% Since delay is significant, we define the Pico's high voltage threshold (PHVT) to be fixed (2.1V)

% Strategy: look forward and backward from the trigger 
% to find when encoder signal crossed PHVT and finished rising
% total delay = rise time to PHVT (10% to PHVT) + Pico interrupt processing time (PHVT to Trigger)

%% Motor Trigger Synchronization & Latency Analyzer (Rising-Edge Input & Trigger)
clear; clc; close all;
[fileName, pathName] = uigetfile('data/*.CSV', 'Select a Data Set');
csvFileName = fullfile(pathName, fileName);

% --- Setup Import Settings to Bypass Tektronix Metadata ---
opts = delimitedTextImportOptions("NumVariables", 5);
opts.DataLines = [17, Inf]; 
opts.Delimiter = ",";
opts.VariableNames = ["Time", "CH1", "CH1_Peak", "CH2", "CH2_Peak"];
opts.VariableTypes = ["double", "double", "double", "double", "double"];

fprintf('Analyzing rising-edge motor sync profile...\n');
data = readtable(csvFileName, opts);
time = data.Time;
ch1_input = data.CH1;    % Encoder Channel A
ch2_trigger = data.CH2;  % Pico Trigger Output

dt = mean(diff(time));
fprintf('Data successfully loaded. Temporal Resolution (dt) = %.2f microseconds\n', dt * 1e6);

%% 1. Pinpoint the Exact Trigger Instant on Channel 2 (Rising Edge)
ch2_low = min(ch2_trigger);
ch2_high = max(ch2_trigger);
ch2_mid = ch2_low + 0.50 * (ch2_high - ch2_low);

% Find the sample index where the Pico Trigger swings past its 50% point
idx_trigger = find(ch2_trigger >= ch2_mid, 1, 'first');
t_trigger_rise = time(idx_trigger);

%% 2. Trace Backwards to find the 5th Encoder RISING Edge (The Cause)
% Increase lookback window slightly to encapsulate the full causal pulse
lookback_samples = 250; 
idx_search_start = max(1, idx_trigger - lookback_samples);
search_window_ch1 = ch1_input(idx_search_start:idx_trigger);
search_window_time = time(idx_search_start:idx_trigger);

% The RP2040 input pin registers a digital logic HIGH when the signal climbs past 2.1V
v_pico_high_threshold = 2.1; 

% --- FIX 1: Search BACKWARD from the trigger to find when it crossed 2.1V ---
% Using 'last' with a '<' condition finds the exact step right before it crossed 2.1V
idx_local_pico_high = find(search_window_ch1 < v_pico_high_threshold, 1, 'last') + 1;
t_pico_registered_high = search_window_time(idx_local_pico_high);

% Characterize the 10% to 90% RC Rise Time of this specific input curve
ch1_high_local = max(search_window_ch1);
ch1_low_local = min(search_window_ch1);
v_rise_10 = ch1_low_local + 0.10 * (ch1_high_local - ch1_low_local);
v_rise_90 = ch1_low_local + 0.90 * (ch1_high_local - ch1_low_local);

% --- FIX 2: Use 'last' to pinpoint when the causal edge crossed thresholds ---
idx_local_rise_start = find(search_window_ch1 < v_rise_10, 1, 'last') + 1;
t_encoder_rise_start = search_window_time(idx_local_rise_start);

idx_local_rise_end = find(search_window_ch1 < v_rise_90, 1, 'last') + 1;
t_encoder_rise_end = search_window_time(idx_local_rise_end);

% Calculate Input RC Properties
rc_rise_time = t_encoder_rise_end - t_encoder_rise_start;

%% 3. Calculate Core Latency and Delay Metrics
software_latency = t_trigger_rise - t_pico_registered_high;
total_delay_from_rise = t_trigger_rise - t_encoder_rise_start;

%% 4. Print System Diagnostics
fprintf('\n================== TIMING REPORT ==================\n');
fprintf('1. INPUT RC WAVEFORM PROPERTIES:\n');
fprintf('   Encoder RC Rise Time (10%% to 90%%): %8.3f microseconds\n', rc_rise_time * 1e6);
fprintf('   Time to reach Pico High (2.1V):   %8.3f microseconds\n', (t_pico_registered_high - t_encoder_rise_start) * 1e6);
fprintf('\n2. MICROCONTROLLER PROCESSING OVERHEAD:\n');
fprintf('   MicroPython Interrupt Latency:    %8.3f microseconds\n', software_latency * 1e6);
fprintf('\n3. CUMULATIVE RADAR ACQUISITION DELAY:\n');
fprintf('   Total Delay (Encoder Rise -> Trigger Rise): %8.3f microseconds\n', total_delay_from_rise * 1e6);
fprintf('===================================================\n');

%% 5. Diagnostic Plot Visual Verification
figure('Name', 'Radar Subsystem Coherent Alignment Analysis', 'Color', 'w');
hold on; grid on;

% Convert time to microseconds relative to the start of the encoder pulse for easy reading
time_us = (time - t_encoder_rise_start) * 1e6;
plot(time_us, ch1_input, 'b-o', 'LineWidth', 1.5, 'DisplayName', 'Ch1: Encoder (5kHz input)');
plot(time_us, ch2_trigger, 'r-s', 'LineWidth', 2, 'DisplayName', 'Ch2: Pico Radar Trigger');

% --- FIX 3: Plot milestones inline with their actual physical coordinates ---
% Green circle is placed at 0 us (t_encoder_rise_start) and its actual measured voltage value
plot(0, search_window_ch1(idx_local_rise_start), 'go', 'MarkerFaceColor', 'g', 'MarkerSize', 8, 'DisplayName', 'Encoder Pulse Start (10%)');

% Yellow square sits directly on the blue trace line exactly where it hits 2.1V
plot((t_pico_registered_high - t_encoder_rise_start)*1e6, search_window_ch1(idx_local_pico_high), 'ks', 'MarkerFaceColor', 'y', 'MarkerSize', 8, 'DisplayName', 'Pico Registers High (2.1V)');

% Red circle sits directly on the red trace line at the 50% trigger threshold
plot((t_trigger_rise - t_encoder_rise_start)*1e6, ch2_trigger(idx_trigger), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 8, 'DisplayName', 'Radar Trigger Fired (50%)');

xlabel('Time Elapsed Since Encoder Pulse Started (\mu s)');
ylabel('Signal Amplitude (Volts)');
title('Multi-Stage Coherent Delay Mapping for Synthetic Aperture Radar Calibration');
legend('Location', 'best');

% Frame the window comfortably around the causal pulse and trigger response
xlim([-50, (total_delay_from_rise * 1e6) + 50]);
ylim([-0.5, 4.0]);
hold off;