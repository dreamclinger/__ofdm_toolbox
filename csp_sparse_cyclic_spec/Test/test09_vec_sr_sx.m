clc; clear; close all

addpath('./Util/')
addpath('./Data/')

% Header 

sig.type = 'fsk'; % 'fsk'

%***************Signal Select**************%
%load fsk.mat
%sig.x = fsk_real(1:64);

load bpsk.mat
sig.x = bpsk(1:64);

%load ofdm.mat
%sig.x = real(ofdm.signal(1:64));

%sig.x=(randn(1,64)); 


load cached_matrix.mat 
disp('load matrix: Gv_save Dv_save D H W_r H_inv B Pn Qm ')


sig.x = sig.x ./ norm(sig.x);
N = length(sig.x);
x = sig.x;

x = x.';

% Equivalent cyclic spectrum

%rx generate, ref[1].eq(8)
rx = [];
for v = 0:N-1 
    for n = 0:(N-1-v)
        rx = [rx, x(1+n)*x(1+n+v)];
	end
end

%R generation, ref[1].eq(7)
R = zeros(N,N);
ptr = 1;
for i = 0:N-1
    num = N - i;
    R(:,i+1) = [rx(ptr:ptr+num-1) zeros(1,i)]';
    ptr = ptr + num;
end

%generate cyclic spectrum 
Rxc = zeros(N,N);
for v = 0:N-1 
	Gv = Gv_save(:,:,v+1);
	Dv = Dv_save(:,:,v+1);
	Rxc = Rxc + Gv*R*Dv; % ref[1].eq(9)
end
Sx = Rxc*D; %ref[1].eq(10)

% Vectorize xcorr and cyclic spectrum
Sx_r = reshape(Sx, 1, N*N); %reshape the cyclic spectrum

% Compressed sampling the signal

cs.sparse = 16;
cs.ratio = 4;
cs.iter = 100;
cs.N = N;
cs.M = round(cs.N/cs.ratio); % num of sensing points
M = cs.M;

Phi = pn_gen(cs.M,cs.N); %random demodulator
Phi_mask = zeros(cs.M, cs.N);
for i = 1:M
    if i*cs.ratio > N
        Phi_mask(i, ((i-1)*cs.ratio+1) : N) = ones(1, N- (i-1)*cs.ratio );
    else    
        Phi_mask(i, ((i-1)*cs.ratio+1) : (i*cs.ratio)) = ones(1, cs.ratio);
    end    
end
Phi = Phi.*Phi_mask;

%load Phi_16_64.mat
y = Phi*x;
Rz = y*y.';

%{
Phi_mask1 = zeros(cs.M, cs.N); %polyphase mask: 'J.N.Laska, The Polyphase Random Demodulator For Wideband Compressive Sensing' 
Phi_mask2 = zeros(cs.M, cs.N); Phi_phase = 1; %Phi_phase < cs.ratio;
for i = 1:M
    if i*cs.ratio > N
        Phi_mask1(i, ((i-1)*cs.ratio+1) : N) = ones(1, N- (i-1)*cs.ratio );
    else    
        Phi_mask1(i, ((i-1)*cs.ratio+1) : (i*cs.ratio)) = ones(1, cs.ratio);
    end    
end
for i = 1:M  
    if (i*cs.ratio+Phi_phase) > N
        Phi_mask2(i, ((i-1)*cs.ratio+1+Phi_phase) : N) = ones(1, N- (i-1)*cs.ratio-Phi_phase);
    else    
        Phi_mask2(i, ((i-1)*cs.ratio+1+Phi_phase) : (i*cs.ratio+Phi_phase)) = ones(1, cs.ratio);
    end    
end
Phi1 = Phi.*Phi_mask1;
Phi2 = Phi.*Phi_mask2;
y1 = Phi1*x; y2 = Phi2*x; Phi = Phi1 + Phi2;
y = y1 + y2;
Rz = y*y.';
%}

%vec{Rz}
rz = [];
for v = 0:M-1 
    for n = 0:(M-1-v)
        rz = [rz, y(1+n)*y(1+n+v)];
	end
end

A = Qm*kron(Phi,Phi)*Pn*H_inv*W_r; % equivalent sensing matrix for CS, ref[1].eq(17)
b = rz.';

% assert: 
t3a = A*Sx_r.';
t3b = b;
if (norm(imag(t3a)-imag(t3b)) < 1e-10) && (norm(real(t3a)-real(t3b)) < 1e-10)
    disp('test: Rz_r = A*Sx_r (?) ... yes');
else
    error('test: Rz_r = A*Sx_r (?) ... no');
end

% Link compressed covariance and vectorized cyclic spectrum 
% H*rx.' = W_r*Sx_r.'; ..ok
% rz.' = Qm*kron(Phi,Phi)*Pn*rx.'; .. ok

%[hatX, ~] = cosamp(b, A, cs.sparse, cs.iter);


cvx_begin
    variable hatX(N^2);
    minimize(norm(hatX,1));
    A*hatX == b;
cvx_end
%threshold = 0.001;
%inx = find(hatX < threshold); hatX(inx) = 0;

hat_m = (vec2mat(hatX, N, N)).';

hat_m_M = [hat_m(:, ((end-16):end)) hat_m(:, (1:(end-17)))];
Sx_M = [Sx(:, ((end-16):end)) Sx(:, (1:(end-17)))];

figure; mesh(abs(Sx_M));
figure; mesh(abs(hat_m_M));

% Extract feature energy from recov spectrum
%[out] = feature_extract(abs(hat_m), 1:N, 0.2, 1:N, 0.2);
%norm(out)
