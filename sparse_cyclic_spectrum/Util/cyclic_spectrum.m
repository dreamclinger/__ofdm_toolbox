function [Spec, f, alpha] = cyclic_spectrum(x, N, fs, M, opt1, opt2)
% cyclic spectrum analysis
% x: signal (must be 1 * N vector)
% N: samples <= len(x) 
% fs: sample rate, [-fs/2 ~ fs/2]
% M: window length 
% author: chenhaomails@gmail.como
% opt1: 'show' => display picture
% opt2: 'signal_len' => set only 1 window for all signal length

win = 'hamming';

d_alpha = fs/N; % freq resolution
alpha = 0:d_alpha:fs-d_alpha; % cyclic resolution
a_len = length(alpha); 

f_len = floor(N/M-1)+1; 
f = -(fs/2-d_alpha*floor(M/2)) + d_alpha*M*(0:f_len-1); % freq sample location

S = zeros(a_len, f_len); 
i = 1; 

% signal fft
X = fftshift(fft(x(1:N))); 
X = X';

%% Loop
for alfa = alpha

    interval_f_N = round(alfa/d_alpha);
    f_N = floor((N-interval_f_N-M)/M)+1; % window num ~= N/M
    
    % window generate
    g = feval(win, M); % return an M-point window  
    window_M = g(:, ones(f_N,1));
    t = 1:M*f_N;
    t = reshape(t, M, f_N);

    % spectral correlation
	if strcmpi(opt2,'signal_len') % only 1 window
    	X1 = X(t).*window_M';
    	X2 = X(t+interval_f_N).*window_M'; 
    	St = conj(X1).*X2;
    	S(i, floor((f_len-f_N)/2)+(1:f_N)) = St/N; %move St to central
    	i = i+1;
	else
		X1 = X(t).*window_M;
    	X2 = X(t+interval_f_N).*window_M; 
    	St = conj(X1).*X2;
    	St = mean(St, 1); % T average
    	S(i, floor((f_len-f_N)/2)+(1:f_N)) = St/N; %move St to central
    	i = i+1;
	end
end

Spec = abs(S);

% figure
if strcmpi(opt1,'show')
	figure;
    mesh(f, alpha, Spec); 
    axis tight;
    xlabel('f'); ylabel('a');    
end
