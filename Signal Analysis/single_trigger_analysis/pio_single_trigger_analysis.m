% pio_single_trigger_analysis.m (test2.m)
% Updated 6/4/2026 by Kailash Rao

% Works for T0006 (PIO)

% PIO takes negligible time (ns) to execute compared to the oscilloscope's current resolution of 1.6us 
% Since delay is negligible, we assume that the Pico's high voltage threshold (PHVT)
% is the same point as where the trigger edge rises (not true for T0002-T0005)

% Strategy: Measure time it takes for encoder signal to reach PHVT = Trigger
% total delay = rise time to PHVT/Trigger (10% to PHVT/Trigger)

%% Single-Trigger Coherent Latency Diagnostic Analyzer
clear; clc; close all;

% --- Configuration ---
csvFileName = 'data/T0006ALL-pio.CSV'; 
lookback_samples = 250; 
lookforward_samples = 50; 

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

%% 2. Trace and Analyze the Causal Encoder Edge (Channel 1)
% Define window stretching back before the trigger and slightly past it
idx_search_start = max(1, idx_trigger - lookback_samples);
idx_search_end = min(length(time), idx_trigger + lookforward_samples); 
search_window_ch1 = ch1_input(idx_search_start:idx_search_end);
search_window_time = time(idx_search_start:idx_search_end);

% The relative location of the trigger inside our cropped window
idx_trigger_rel = idx_trigger - idx_search_start + 1;

% --- DYNAMIC FIX: Measure the exact voltage that tripped the PIO hardware ---
v_pico_high_threshold = ch1_input(idx_trigger); 

% Find the step right before it crossed this hardware threshold
idx_last_low = find(search_window_ch1(1:idx_trigger_rel) < v_pico_high_threshold, 1, 'last');
if isempty(idx_last_low)
    idx_local_pico_high = idx_trigger_rel;
else
    idx_local_pico_high = idx_last_low + 1;
end
t_pico_registered_high = search_window_time(idx_local_pico_high);

% Characterize the 10% to 90% RC Rise Time of this specific input curve
ch1_high_local = max(search_window_ch1);
ch1_low_local = min(search_window_ch1);
v_rise_10 = ch1_low_local + 0.10 * (ch1_high_local - ch1_low_local);
v_rise_90 = ch1_low_local + 0.90 * (ch1_high_local - ch1_low_local);

% Pinpoint 10% start (Searching backwards)
idx_local_rise_start = find(search_window_ch1(1:idx_trigger_rel) < v_rise_10, 1, 'last') + 1;
t_encoder_rise_start = search_window_time(idx_local_rise_start);

% Pinpoint 90% end (Searching FORWARDS from the 10% start mark)
idx_relative_rise_end = find(search_window_ch1(idx_local_rise_start:end) >= v_rise_90, 1, 'first');
if isempty(idx_relative_rise_end)
    idx_local_rise_end = length(search_window_ch1);
else
    idx_local_rise_end = idx_local_rise_start + idx_relative_rise_end - 1;
end
t_encoder_rise_end = search_window_time(idx_local_rise_end);

% Calculate Input RC Properties
rc_rise_time = t_encoder_rise_end - t_encoder_rise_start;

%% 3. Calculate Core Latency and Delay Metrics
% MicroPython / PIO hardware overhead
software_latency = t_trigger_rise - t_pico_registered_high;

% Complete alignment delay from initial encoder edge to radar pulse
total_delay_from_rise = t_trigger_rise - t_encoder_rise_start;

%% 4. Print System Diagnostics
fprintf('\n================== TIMING REPORT ==================\n');
fprintf('1. HARDWARE SENSITIVITY:\n');
fprintf('   Hardware Trip Voltage Detected:   %8.2f Volts\n', v_pico_high_threshold);
fprintf('\n2. INPUT RC WAVEFORM PROPERTIES:\n');
fprintf('   Encoder RC Rise Time (10%%-90%%):   %8.3f microseconds\n', rc_rise_time * 1e6);
fprintf('   Time to hit Trip Threshold:       %8.3f microseconds\n', (t_pico_registered_high - t_encoder_rise_start) * 1e6);
fprintf('\n3. PROCESSING OVERHEAD:\n');
fprintf('   PIO Engine Latency:               %8.3f microseconds\n', software_latency * 1e6);
fprintf('\n4. CUMULATIVE ALIGNMENT DELAY:\n');
fprintf('   Total Delay (Encoder -> Trigger): %8.3f microseconds\n', total_delay_from_rise * 1e6);
fprintf('===================================================\n');

%% 5. Diagnostic Plot Visual Verification
figure('Name', 'Radar Subsystem Coherent Alignment Analysis', 'Color', 'w');
hold on; grid on;

% Convert time to microseconds relative to the start of the encoder pulse
time_us = (time(idx_search_start:idx_search_end) - t_encoder_rise_start) * 1e6;

plot(time_us, search_window_ch1, 'b-o', 'LineWidth', 1.5, 'DisplayName', 'Ch1: Encoder Input');
plot(time_us, ch2_trigger(idx_search_start:idx_search_end), 'r-s', 'LineWidth', 2, 'DisplayName', 'Ch2: PIO Trigger');

% Plot milestones exactly on the data points
plot(0, search_window_ch1(idx_local_rise_start), 'go', 'MarkerFaceColor', 'g', 'MarkerSize', 8, 'DisplayName', 'Encoder Pulse Start (10%)');
plot((t_pico_registered_high - t_encoder_rise_start)*1e6, search_window_ch1(idx_local_pico_high), 'ks', 'MarkerFaceColor', 'y', 'MarkerSize', 8, 'DisplayName', sprintf('PIO Triggered (%.2fV)', v_pico_high_threshold));
plot((t_trigger_rise - t_encoder_rise_start)*1e6, ch2_trigger(idx_trigger), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 8, 'DisplayName', 'Radar Trigger Fired (50%)');

xlabel('Time Elapsed Since Encoder Pulse Started (\mu s)');
ylabel('Signal Amplitude (Volts)');
title('Multi-Stage Coherent Delay Mapping (PIO Hardware Engine)');
legend('Location', 'best');
xlim([-10, (total_delay_from_rise * 1e6) + 15]);
ylim([-0.5, 4.0]);
hold off;