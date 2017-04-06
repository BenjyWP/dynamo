classdef rpDiscreteSample < RandProcess
%rpDiscreteSample Sample from diff process at each state
%
% Random process that samples from a different discrete distribution
% for each time period independant of previous time period's state
%
% Constructor: obj = rpDiscreteSample(v_list, p_list)
%
% Required inputs/properties:
%  v_list: cell row vector with one cell per time period containing a
%           numeric col vector of possible values
% Optional:
%  p_list: matching cell vector with corresponing probabilites for each
%           value. The sum of each col must equal 1. If p_list is not
%           provided, a uniform distribution across all values in the
%           corresponding v_list is assumed
%
% Additional properties (set using obj.PROPERTY):
%  None
%
% Notes:
%  - For any t greater than the max set in the ValueList, the final value
%    from the list is assumed to be held constant
%  - For non-integer times, the output is assumed to remain at the value
%    corresponding to the previous integer time step (Zero-order hold)
%
% Examples:
% % 1-D state with constant (in time) probability distribution 
% >>> rng(0); s = rpDiscreteSample({[0, 1, 2, 3]'}, {[0.1, 0.5, 0.35, 0.05]'});
%
% >>> s.sample()
% ans = 
%        3
% 
% see also RandProc, rpMarkov, rpList, rpLattice
%
% originally by Bryan Palmintier 2011

% HISTORY
% ver     date    time       who     changes made
% ---  ---------- -----  ----------- ---------------------------------------
%  10  2016-04-05 14:53  BryanP      First step to value-only states: fixed dlistnext 
%   9  2016-xx           BryanP      Corrected time indexing (reported to dynamo 3/2017) 
%   8  2016-05-01 03:25  BryanP      Expose sample() and add support for vectorized samples
%   7  2016-04-29 00:25  BryanP      Use uniform probability if P_List not provided
%   6  2012-04-17 08:55  BryanP      Reworked cdf for sim/sample
%   5  2011-11-15 18:30  BryanP      Corrected bug with sample return order
%   4  2011-06-09 16:00  BryanP      match input shape for dnum2val and dval2num
%   3  2011-05-03 01:04  BryanP      Fixed:
%                                      - time/index in dlistnext & prev
%                                      - random sample on reset
%                                      - dlist state order for non-ascending values
%   2  2011-04-12 09:45  BryanP      Initial coding complete
%   1  2011-04-08 14:30  BryanP      Adapted from rpLattice v6


    properties
        t = 1;        % Current time
    end

    % Read only properties
    properties (GetAccess = 'public', SetAccess='protected')
        Vlist = {};    % cell row vector of values
        Plist = {};    % cell row vector of probabilities

        cur_state = NaN;    %Current state number for simulation
    end

    % Internal properties
    properties (Access='protected')
        CdfList = {};   % cumulative distribution for each time period
        Tmax = 1;       % Largest time with specified distribution
        Tol = 1e-6;      % Tolerance for checking probabilities sum to 1
    end

    methods (Access = protected)
        %% ===== Helper Functions
        function [state_list, prob] = state_info (obj, t )
        % STATE_INFO Helper function to return full set of state
        % information for a given time
            if t < 1
                error('RandProcess:InvalidTime', 'Only t>1 valid for rpDiscreteSample')
            else
                % make sure time is an integer
                t = floor(t);

                % and use t=Tmax for any t>Tmax
                t = min(t, obj.Tmax);

                %if we get here, we know the state is valid
                state_list = obj.Vlist{t};
                prob = obj.Plist{t};
            end
        end

    end

    methods
        %% ===== Constructor & related
        function obj = rpDiscreteSample(v_list, p_list)
            % Support zero parameter calls to constructor for special
            % MATLAB situations (see help files)
            if nargin == 0
                obj.Vlist = v_list;
                obj.Plist = p_list;
            end
            
            %-- Extract dimensional data
            %Note: Tmax is the max t with a unique value list. passing
            %a t>Tmax will simply return the Tmax values (zero order
            %hold)
            obj.Tmax = length(v_list);
            obj.N_dim = size(v_list{1},2);

            % If probabilites not provided, assume uniform across all
            % values
            if nargin < 2
                obj.Plist = cell(size(v_list));
                for t_idx = 1:obj.Tmax
                    num_states = size(v_list{t_idx},1);
                    obj.Plist{t_idx} = ones(num_states,1) ./ num_states;
                end

            else
                obj.Plist = p_list;
            end
            
            % Store state value list
            obj.Vlist = v_list;


            % Loop through time for setting up additional parameters
            for t_idx = 1:obj.Tmax
                %Create Cumulative distribution function for easier
                %mapping of random samples
                obj.CdfList{t_idx} = cumsum(obj.Plist{t_idx});

                %Check for valid probability vectors 
                %  Probability must sum to 1
                if abs(obj.CdfList{t_idx}(end) - 1) > obj.Tol
                    error('RandProc:ProbSum1', 'Probabilities must sum to 1.0 for t=%d', t_idx)
                end

                %  Must be same size as value list
                if size(obj.Plist{t_idx}) ~= size(obj.Vlist{t_idx})
                    error('rpDiscreteSample:ValProbMismatch', 'Value & Probability vectors must have equal size for time=%d', t_idx)
                end
            end
            obj.reset();
        end
        
        %% == Additional public methods
        function state_list = sample(obj, t, N, varargin)
            %SAMPLE draw samples for the given time
            % Note: if N is not specified, defaults to a single sample
            if nargin < 2
                t = obj.t;
            end
            if nargin < 3
                N = 1;
            end

            %Handle any non integer or large values for time
            t = min(floor(t), obj.Tmax);

            idx_at_t = zeros(N,1);
            for samp_idx = 1:N
                idx_at_t(samp_idx) = find(rand(1) <= obj.CdfList{t}, 1, 'first');
            end
            state_list = obj.Vlist{t}(idx_at_t,:);
        end

        %% ===== Support for discrete usage
        % These need to be defined even for continuous processes, for
        % compatability with DP.

        function state_list = dlist (obj, t)
        % DLIST List possible discrete states
        %
        % List possible discrete states by number for given time
        % if t is not listed, the states for the current simulation time
        % are returned.
        %
        % To get a list of all possible states pass with t='all'
            if nargin < 2 || isempty(t)
                state_list = obj.dlist(obj.t);
            elseif (ischar(t) && strcmp(t, 'all'))
                state_list = unique(cell2mat(obj.Vlist'),'rows');
            else
                state_list = obj.state_info(t);
            end
        end

        function [state_list, probability_list] = dlistnext (obj, state, t )
        % DLISTNEXT List next discrete states & probabilities
        %
        % List possible next states (by number) along with conditional
        % probability P(s_{t+1} | s_t) Since the samples are independant
        % of each other (ie not path dependant), this simplifies to
        % P(s_{t+1})
        %
        % If t and/or state are not defined, the current simulation time
        % and state are assumed
            if nargin < 3
                [state_list, probability_list] = obj.dlistnext(state, obj.t);
                return
            end

            t = min(floor(t), obj.Tmax);
            if nargin > 2 && not(isempty(state)) && ...
                          not(all(ismember(state,obj.Vlist{t}, 'rows')))
                error('RandProcess:InvalidState', 'State %s is not valid at time %d', state, t)
            else
                %if we get here, we know the state is valid
                % t+1 is right b/c want next state
                [state_list, probability_list] = obj.state_info(t+1);
            end
        end

        function state_series = dsim(obj, t_list, initial_value) %#ok<INUSD>
        % DSIM Simulate discrete process.
        %
        % A column vector for t is assumed to be a series of times for
        % which to return results. Intermediate times are also computed, if
        % needed, but not returned. The initial value is not returned in
        % the value series. Only one simulation is run, such that out of
        % order times will be sorted before simulation and duplicate times
        % will return the same result
        %
        % Invalid times (t<1) return NaN
        %
        % Note: after calling dsim, the process internal time will be set to
        % the final value of t_list

            %identify valid simulation times
            ok = (t_list >= 1);

            %initialize outputs
            state_series = zeros(size(t_list),obj.N_dim);
            state_series(not(ok),:) = NaN;

            %only simulate valid values of t_list
            t_list = t_list(ok);

            %only run the simulation if there are valid times to simulate.
            %If not, we have already filled the value list with NaNs and
            %can skip ahead to the state list if requested.
            if not(isempty(t_list))
                %Find times we need to sample
                [t_list, ~, sample_map] = unique(t_list);

                %initalize sample results vectors
                v_list = zeros(size(t_list, obj.N_dim));

                %Sample all required times
                for t_idx = 1:length(t_list)
                    v_list = obj.sample(t_list(t_idx));
                end

                %Set the current state
                obj.t = t_list(end);
                obj.cur_state = v_list(end, :);

                %Reorder samples to match the valid input times
                v_list = v_list(sample_map,:);

                %Now Stuff the correct values into the full output list
                state_series(ok,:) = v_list;
            end
        end

        %% ===== General (discrete or continuous) Methods
        function state_series = sim(obj, t_list, initial_state)
        % SIM Simulate process for desired (continuous) times
        %
        % A column vector for t is assumed to be a series of times for
        % which to return results. Intermediate times are also computed, if
        % needed. The initial value is not returned in the value series.
        %
        % Function must handle arbitrary positive values for t_list
        % Invalid times (t<=1) return NaN
        %
        % Note: after calling sim, the process internal time will be set to
        % the final value of t_list
        %
        % This implementation typically rounds down to the nearest integer
        % (zero order hold)
            if nargin < 3
                initial_state = [];
            end
            state_series = obj.dsim(floor(t_list), initial_state);
        end

        function value_range = range(obj, t)
        % RANGE Find value range for given time
        %
        % Returns vector with [min max] value range for specified time
        % if t is not provided, the range for the current simulation time
        % is returned.
        %
        % To get the possible range across all times use t='all'
            if nargin < 2 || isempty(t)
                t= obj.t;
            end

            if ischar(t) && strcmp(t, 'all')
                state_list_to_range = cell2mat(obj.Vlist');
            else
                %Handle any non-integer or large values
                t = min(floor(t), obj.Tmax);

                if t < 1;
                    error('RandProcess:InvalidTime', 'Only t>=1 valid for rpDiscreteSample')
                else
                    state_list_to_range = obj.Vlist{t};
                end
            end
            value_range = [min(state_list_to_range); max(state_list_to_range)];
        end


        %% ===== Additional simulation support
        function [state, t] = step(obj, delta_t)
        %STEP simulate forward or backward
        %
        % by default steps forward by delta_t = 1
            if nargin < 2
                delta_t = 1;
            end
            %compute the proposed new time
            new_t = obj.t + delta_t;

            %check if it is valid, if not return empty results
            if new_t < 1
                state = [];
                t = obj.t;
                return
            else
                %if new time is valid simulate forward or back as needed
                if floor(obj.t) == floor(new_t)
                    %No need to actually change, b/c we have discrete steps
                    %that round
                    state = obj.cur_state;
                else
                    t = new_t;
                    state = obj.sample(t);

                    % Update our stored state
                    obj.t = t;
                    obj.cur_state = state;

                end

            end

        end

        function [state, t] = curState(obj)
        %CURSTATE Return the current state of the simulation
            state = obj.cur_state;
            t = obj.t;
        end

        function reset(obj, initial_state)
        %RESET reset simulation to t=1 and provided initial_value. If no
        %initial value provided, we randomly sample the first state
            obj.t = 1;
            if nargin > 1
                obj.cur_state = initial_state;
            else
                obj.cur_state = obj.Vlist{1}(find(rand() <= obj.CdfList{obj.t}, 1, 'first'), :);
            end
        end

    end

end
