function val = resolveParam(name, wasProvided, argVal, default)
% resolveParam  Resolve a parameter value using 3-tier priority:
%
%   val = resolveParam(name, wasProvided, argVal, default)
%
%   Resolution order:
%     1. Explicit argument   — if wasProvided is true and argVal is not empty
%     2. Base workspace var  — if a variable named 'name' exists in base workspace
%     3. Default value       — fallback
%
%   This enables stimulus functions to be controlled from Experimenter5000
%   (a script whose variables live in the base workspace) without modifying
%   Experimenter5000 itself.
%
%   Inputs:
%     name         - string, variable name to look for in base workspace
%     wasProvided  - logical, true if the caller received this as an explicit arg
%     argVal       - the explicit argument value (may be empty)
%     default      - fallback value if neither arg nor workspace variable exists
%
%   Example:
%     flickerHz = resolveParam('stimFlickerHz', nargin >= 1, flickerHz, 4);

    if wasProvided && ~isempty(argVal)
        val = argVal;
    else
        try
            val = evalin('base', name);
        catch
            val = default;
        end
    end
end
