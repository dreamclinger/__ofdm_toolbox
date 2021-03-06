function [Spec_f_cs, Spec_f, f, alpha] = cs_cyclic_spectrum(x, N, fs, opt1)
% x: signal (1 * N vector)
% N: samples <= len(x) 
% fs: sample rate
% author: chenhaomails@gmail.com
% opt1: 'show' => display picture

M = 1;

d_tau = fs/N; % time resolution
tau = 0:d_tau:fs-d_tau; % delay resolution
tau_len = length(tau); 

t_len = floor(N/M-1)+1; 
t_n = -(fs/2-d_tau*floor(M/2)) + d_tau*M*(0:t_len-1); % freq sample location

S = zeros(tau_len, t_len); 
i = 1; 

% signal fft
X = fftshift(fft(x(1:N))); 
X = X';
x = x';

%normal xcorr and cyclic_spec

%% Loop
for alfa = tau

    interval_tau = round(alfa/d_tau); % tau
    T_N = floor((N-interval_tau-M)/M)+1; 
    
    t = 1:M*T_N;
    t = reshape(t, M, T_N);

    % spectral correlation
	x1 = x(t);
	x2 = x(t+interval_tau); 
   	St = conj(x1).*x2;
   	S(i, floor((t_len-T_N)/2)+(1:T_N)) = St/N; %move St to central
   	i = i+1;
end

Spec_t = abs(S);
%for ii = 1:N
%	%Y(ii,:) = simple_fft_tau(S(ii, :), N, tau);
%    Y(ii,:) = fftshift(fft(S(ii, :)));
%end
%for jj = 1:N
%	Z(:,jj) = fftshift(fft(Y(:, jj)));
%end
D = dftmtx(N);
W = D*S*D;
Z = fftshift(W);
Spec_f = abs(Z);

% compressed xcorr
cs.sparse = 16;
cs.ratio = 8;
cs.iter = 32;
cs.N = N;
cs.M = round(cs.N/cs.ratio);

% sensing 1
%Phi = randn(cs.M,cs.N);

% sensing 2
temp = toeplitz(randn(1,cs.N));
Phi = temp(1:cs.M, 1:cs.N);
Phi = Phi./norm(Phi);

y = Phi*x;

Sy = zeros(cs.M, cs.M); 
i = 1; 

for alfa = tau(1:cs.M)
    interval_tau = round(alfa/d_tau); % tau
    T_N = floor((cs.M-interval_tau-M)/M)+1; 
    
    % window generate
    t = 1:M*T_N;
    t = reshape(t, M, T_N);

    % spectral correlation
	y1 = y(t);
	y2 = y(t+interval_tau); 
   	Syt = conj(y1).*y2;
   	Sy(i, (1:T_N)) = Syt/cs.M; %move St to central
   	i = i+1;
end

% sparse reconstruction 3, fails
% S = DRD;
% R = inv(D) S inv(D)
% Rz = ARA'
% Rz = A inv(D) S inv(D) A' ;
% Rz * P = A inv(D) S, where P = pinv (inv(D) * A);

% sparse recon 4, vec{} and kron{}, fails since memory full.

% sparse recon 5, alternatively cosamp:
for ii = 1:cs.M
    A= Phi*inv(D);
    for iter = 1:2
        if iter == 1    
            b = Sy(:,ii); 
        else
            b = Sy(ii,:)';
        end
        cvx_begin
            variable x(N);
            minimize(norm(x,1));
            A*x == b;
        cvx_end
        if iter == 1    
            hat1(:,ii) = x';
        else
            hat2(ii,:) = x;
        end 
    end
	%[hat1(:,ii), ~] = cosamp(Sy(:,ii), Phi*inv(D), 32, 100);
	%[hat2(ii,:), ~] = cosamp(Sy(ii,:)', Phi*inv(D), 32, 100);
end
W1 = fftshift(hat1);
W2 = fftshift(hat2);
W = W1 * W2;
Spec_f_cs = abs(W);

% figure
if strcmpi(opt1,'show')
	d_alpha = fs/N; % freq resolution
	alpha = 0:d_alpha:fs-d_alpha; % cyclic resolution
	a_len = length(alpha); 
	f_len = floor(N/M-1)+1; 
	f = -(fs/2-d_alpha*floor(M/2)) + d_alpha*M*(0:f_len-1); % freq sample location

%normal xcorr and cyclic_spec

	figure;
    mesh(t_n, tau, Spec_t); 
    axis tight;
    xlabel('t'); ylabel('tau');    
	figure;
	d_alpha = fs/N; % freq resolution
	alpha = 0:d_alpha:fs-d_alpha; % cyclic resolution
	a_len = length(alpha); 
	f_len = floor(N/M-1)+1; 
	f = -(fs/2-d_alpha*floor(M/2)) + d_alpha*M*(0:f_len-1); % freq sample location
    mesh(f, alpha, Spec_f); 
    axis tight;
    xlabel('f'); ylabel('a');    
	figure;
    mesh(f, alpha, Spec_f_cs); 
    axis tight;
    xlabel('f'); ylabel('a');    
	%figure;
	%plot(Spec_f_cs, '*');
end
