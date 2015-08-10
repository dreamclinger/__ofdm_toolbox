clc; clear; close all

addpath('./Util/')
addpath('./Data/')


% Header 

sig.type = 'fsk'; % 'fsk'
sig.fs = 1;
sig.M = 1;

if strcmpi(sig.type,'fsk') % default signal
	load fsk.mat             
else
	error('signal type not exist!!');
end

sig.x = fsk_real(1:64);
%sig.x = fsk_real(65:128);
%sig.x=(randn(1,64)); 

sig.x = sig.x ./ norm(sig.x);
sig.N = length(sig.x);
fs = sig.fs;
N = sig.N;
x = sig.x;
opt1 = 'show';

M = 1;

d_tau = fs/N; % time resolution
tau = 0:d_tau:fs-d_tau; % delay resolution
tau_len = length(tau); 

t_len = floor(N/M-1)+1; 
t_n = -(fs/2-d_tau*floor(M/2)) + d_tau*M*(0:t_len-1); % freq sample location

S = zeros(tau_len, t_len); 
i = 1; 

x = x';

% Equivalent cyclic spectrum
% Rx = x*x' <=> S in cyclic_spectrum.m 
Dft = dctmtx(N);%dftmtx(N);
%D = fftshift(Dft); % choose DFT matrix
D = Dft;
Rx_o = x*x';
%Sx = D*Rx*D;


%the following canbe optimised !!!

%R generation, ref[1].eq(7)
Rx = zeros(N,N);
for nn = 1:N
	for v = 1:(N-nn+1) % last nn-1 items in each row is zero.
		%Rx(nn,v) = x(nn)* x(mod(nn+v-1, N));
        Rx(nn,v) = x(nn)* x(nn+v-1);
	end
end

%vec{R} generate, ref[1].eq(8)
B = [];
tmp = eye(N*N);
for nn = 1:N
	for v = 1:(N-nn+1) 
		q = (v-1)*N + (nn-1) + 1;  %q = nN + v, ~[0, N-1] => ~[1,N]
		B = [B, tmp(:, q)];
	end
end

%Pn, Qm generate, ref[1].eq(43,44)
Pn = zeros(N*N, N*(N+1)/2);
Qn = zeros(N*N, N*(N+1)/2); %what's kron delta?
for v = 1:N
	for nn = 1:(N-v+1)  %eq(43)
		p = (v-1)*N - (v-1)*(v-2)/2 + (nn-1) + 1;
		q1 = (v-1+nn-1)*N + (nn-1) + 1;  %eq(42)
		q2 = (nn-1)*N + (nn-1) + (v-1) + 1;  
		Pn(q1, p) = 1; Pn(q2, p) = 1;
		if (v == 1)
			kron_delta = 1;
		else
			kron_delta = 0;
		end 
		Qn(p,q1) = 1; Qn(p,q2) = 1/2 + (1/2)*kron_delta;
	end
end

%rx generate, ref[1].eq(8)
rx = [];
for nn = 1:N
	for v = 1:(N-nn+1) 
		tmp = Rx(nn,v);
		rx = [rx, tmp];
	end
end

% assert: 
t0a = B*rx'; 
t0b = reshape(Rx, 1, N*N);
if ( (norm(t0a - t0b') / length(t0a)) < 0.003)
    disp(' vec{R} = B*rx (?) ... yes');
else
    error(' vec{R} = B*rx (?) ... no');
end

%generate cyclic spectrum 
%ver1: Sx = D*Rx*D;
%ver2:
Sx_tmp = zeros(N,N);
for v = 1:N 
	Gv = zeros(N,N);
	Dv = zeros(N,N);
	for nn = 1:N
		for alph = 1:N
			Gv(nn, alph) = exp(-2*pi*sqrt(-1)*(alph-1)*(nn-1+((v-1)/2))/N); % recall dftmtx(N): each W(j,k)= exp(-2*pi*sqrt(-1)*(j-1)*(k-1)/N); 
		end
	end
	Dv(v,v) = 1;  % make groups of diag matrix that all entries are '0' but (v,v) = 1
	Sx_tmp = Sx_tmp + Gv*Rx*Dv; % ref[1].eq(9)
	% save Gv, Dv
	Gv_save(:,:,v) = Gv;
	Dv_save(:,:,v) = Dv;
end
Sx = Sx_tmp*D; %ref[1].eq(10), but eq(12) says vec{Sx * F^-1}... ?

% Vectorize xcorr and cyclic spectrum
matrix_load = 'no';
Sx_r = reshape(Sx, 1, N*N); %reshape the cyclic spectrum
%rx = reshape(Rx, 1, N*N); %reshape the xcorr
%B = eye(N^2);
%H = kron((eye(N))',D)*B;
H_tmp = zeros(N^2,N^2);
for v = 1:N % calculate the matrix that map Rx => Sx_tmp_sum
	Gv = Gv_save(:,:,v);
	Dv = Dv_save(:,:,v);
	H_tmp = H_tmp + kron(Dv', Gv);  
end
H = H_tmp* B; 
W_r = kron((inv(D))', eye(N));
H_inv = ((H'*H)^(-1))*H'; %rank(H) = 4096;

% assert: 
t1a = W_r*Sx_r'; 
t1b = H*rx';
if ( (norm(t1a - t1b) / length(t1a)) < 0.003)
    disp('test: H*rx == W_r*Sx_r (?) ... yes');
else
    error('test: H*rx == W_r*Sx_r (?) ... no');
end
t2a = H_inv*W_r*Sx_r';
t2b = rx';
if ( (norm(t2a - t2b) / length(t2a)) < 0.003) % problem, not pass, why ?
    disp('test: rx == H_inv*W_r*Sx_r (?) ... yes');
else
    error('test: rx == H_inv*W_r*Sx_r (?) ... no');
end

% Compressed sampling the signal
cs.sparse = 16;
cs.ratio = 4;
cs.iter = 32;
cs.N = N;
cs.M = round(cs.N/cs.ratio); % num of sensing points
Phi = pn_gen(cs.M,cs.N);
y = Phi*x;

%R generation via CS sampls, ref[1].eq(14)
Cy = zeros(cs.M,cs.M);
for nn = 1:cs.M
	for v = 1:(cs.M-nn+1) % last nn-1 items in each row is zero.
		%Cy(nn,v) = x(nn)* x(mod(nn+v-1, cs.M));
        Cy(nn,v) = y(nn)* y(nn+v-1);
	end
end

Cy_r = reshape(Cy, 1, cs.M*cs.M);
Qm = eye(cs.M*cs.M); Pn = eye(N*N);
A = Qm*kron(Phi,Phi)*Pn*H_inv*W_r; % equivalent sensing matrix for CS, ref[1].eq(17)
b = Cy_r';

% assert: 
t3a = A*Sx_r';
t3b = b;
if ( (norm(t3a - t3b) / length(t3a)) < 0.005)
    disp('test: Cy_r = A*Sx_r (?) ... yes');
else
    error('test: Cy_r = A*Sx_r (?) ... no');
end

% Link compressed covariance and vectorized cyclic spectrum 
% 1 Phi*x*x'*Phi' = Phi*Rx*Phi' =y*y' = Cy; ..ok
% 2. H*rx' = W_r*Sx_r'; ..ok
% 3. Cy_r' = kron(Phi,Phi)*rx'; .. ok
% so Cy_r' = kron(Phi,Phi)*H_inv*W_r*rx', where rx is sparse;
% Problem: sparse hat_m is not concentrated!

cvx_begin
    variable hatX(N^2);
    minimize(norm(hatX,1));
    A*hatX == b;
cvx_end
hat_m = (vec2mat(hatX, N, N))';
figure; mesh(abs(hat_m));

% Extract feature energy from recov spectrum
%[out] = feature_extract(abs(hat_m), 1:N, 0.2, 1:N, 0.2);
%norm(out)
