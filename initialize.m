function p = initialize (T, W, M, A, varargin)
% allocate the parameter structure
if (T <= 0)
    error('T must be >0');
end
if (W < 0)
    error('W must be >=0');
end
if (M <= 0)
    error('M must be >0');
end
if (2*W > M)
    error('W is too large');
end
if (-A > W || A + W > M - W)
    error('A is too large');
end

% if we're going to bin the data make sure that zero is on a bin boundary by adjusting A
if (nargin ==5)
    zero = (W + A)/(M + A);
    zero = floor(zero*varargin{1} + 0.5)/varargin{1};
    A = (M*zero - W)/(1 - zero);
end
%%
% standard parameters
p.T = T;
p.M = M;
p.W = W;
p.A = A;
%%
% actual parameters formulas from biexponential paper
p.w = p.W/(p.M+p.A);
p.x2 = p.A/(p.M+p.A);
p.x1 = p.x2 + p.w;
p.x0 = p.x2 + 2*p.w;
p.b = (p.M+p.A)*log(10);
p.d = solve_RTSAFE(p.b,p.w);
c_a = exp(p.x0*(p.b+p.d));
mf_a = exp(p.b*p.x1) - c_a/exp(p.d*p.x1);
p.a = p.T/((exp(p.b) - mf_a) - c_a/exp(p.d));
p.c = c_a*p.a;
p.f = -mf_a*p.a;
%%
% use Taylor series near x1, i.e., data zero to avoid round off problems of formal definition
p.xTaylor = p.x1 + p.w/4;
% compute coefficients of the Taylor series
posCoef = p.a*exp(p.b*p.x1);
negCoef = -p.c/exp(p.d*p.x1);
% 16 is enough for full precision of typical scales
p.taylor = zeros(16,1);
for i=1:16
    posCoef = posCoef*p.b/i;
    negCoef = -negCoef*p.d/i;
    p.taylor(i) = posCoef + negCoef;
end
p.taylor(2) = 0;
if (nargin == 5)
    p.bins = varargin{1};
    p.lookup = inverse(p,linspace(0,1,p.bins+1));
end
end

function d = solve_RTSAFE(b,w)
% Paraphrasing of c++ implementation by Wayne A. Moore found at
% http://onlinelibrary.wiley.com/doi/10.1002/cyto.a.22030/full
    % w == 0 means its really arcsinh
    if(w==0)
        d = b;
        return;
    else
        % Precision is the same as that of b
        tolerance = 2*eps(b);
        % Based on RTSAFE from Numerical Recepies 1st Edition
        % Bracket the root
        d_lo = 0;
        d_hi = b;
        % Bisection first step
        d = (d_lo+d_hi)/2;
        last_delta = d_hi - d_lo;
        % evaluate the f(w,b) = 2 * (ln(d) - ln(b)) + w * (b + d) and its
        % derrivative
        f_b = -2*log(b) + w*b;
        f = 2*log(d) + w*d + f_b;
        last_f = NaN;
        for i=1:20
            df = 2/d + w;
            % if Newton's method would step outside the bracke or if it isn't converging quickly enough
            if(((d - d_hi) * df - f) * ((d - d_lo) * df - f) >= 0 || abs(1.9 * f) > abs(last_delta * df))
                % take a bisection step
                delta = (d_hi - d_lo)/2;
                d = d_lo + delta;
                if(d==d_lo)
                    return; % nothing changed, we're done
                end
            else
                % otherwise take a Newton's method step
                delta = f/df;
                t = d;
                d = d - delta;
                if (d == t)
                    return; % nothing changed, we're done
                end
            end
            % if we've reached the desired precision we're done
            if(abs(delta)<tolerance)
                return;
            end
            last_delta = delta;
            % recompute the function
            f = 2 * log(d) + w * d + f_b;
            if (f == 0 || f == last_f)
                return; % found the root or are not going to get any closer
            end
            last_f = f;
            % update the bracketing interval
            if(f < 0)
                d_lo = d;
            else
                d_hi = d;
            end
        end
        error('exceeded maximum iterations in solve()');
    end
end

function out = inverse(p,scale)
% Paraphrasing of c++ implementation by Wayne A. Moore found at
% http://onlinelibrary.wiley.com/doi/10.1002/cyto.a.22030/full
% reflect negative scale regions
out = zeros(size(scale));
for i = 1:length(scale(:))
    negative = scale(i) < p.x1;
    if (negative)
        scale(i) = 2*p.x1 - scale(i);
    end
    % compute the biexponential
    if (scale(i) < p.xTaylor)
        % near x1, i.e., data zero use the series expansion
        inverse = seriesBiexponential(p,scale(i));
    else
        % this formulation has better roundoff behavior
        inverse = (p.a*exp(p.b*scale(i)) + p.f) - p.c/exp(p.d*scale(i));
    end
    
    % handle scale(i) for negative values
    if (negative)
        out(i) = -inverse;
    else
        out(i) = inverse;
    end
end
end