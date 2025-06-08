- Work item name: Refactor `Get-UIConfig`
- Work item issue (e.g. what is the work item solving): The `Get-UIConfig` function currently accesses UI elements directly, making it tightly coupled to the main UI script and harder to maintain and test. This work item will refactor it to accept a central state object, improving modularity and aligning with the project's overall refactoring goals.
- Work Item plan:
  - What the plan is: I will modify the `Get-UIConfig` function in `FFUUI.Core.psm1`. The function will be updated to accept a single `$State` object as a parameter. Inside the function, all references to UI controls will be changed to access them from the `$State.Controls` hashtable. This will decouple the function from the main script's global variables. I will then update the call to this function in `BuildFFUVM_UI.ps1` to pass the new `$script:uiState` object.
  - Files modified:
    - `FFUDevelopment/FFUUI.Core/FFUUI.Core.psm1`
    - `FFUDevelopment/BuildFFUVM_UI.ps1`
  - Global/script variables and/or parameters created: None
  - Functions created: None
  - Any other important functionality: This change is a key part of the "Tame the script: Scope with a Central State Object" initiative. It will make the code cleaner, more maintainable, and easier to debug.

# Current Work Item

# Summary of Changes
- **Refactored `Get-UIConfig` function**:
  - Moved the `Get-UIConfig` function from `BuildFFUVM_UI.ps1` to the `FFUUI.Core.psm1` module to improve code modularity and separation of concerns.
  - Modified the function to accept a central `$State` object as a parameter, eliminating direct dependencies on global UI variables like `$window`.
  - Updated all internal logic within `Get-UIConfig` to retrieve UI control values from the `$State.Controls` hashtable (e.g., `$State.Controls.chkCompactOS.IsChecked`).
  - Updated the function calls in `BuildFFUVM_UI.ps1` (within the `btnRun` and `btnBuildConfig` click events) to pass the `$script:uiState` object to the refactored function.
  - Exported `Get-UIConfig` from the `FFUUI.Core.psm1` module, making it accessible to the main UI script.
- **Files Modified**:
  - `FFUDevelopment/BuildFFUVM_UI.ps1`: Removed the original function definition and updated the calls.
  - `FFUDevelopment/FFUUI.Core/FFUUI.Core.psm1`: Added the refactored function and exported it.
