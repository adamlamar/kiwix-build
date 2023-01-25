REM ========================================================
REM Install libkiwix
git clone --branch split-size https://github.com/adamlamar/libkiwix.git || exit /b 1
cd libkiwix
set CPPFLAGS="-I%EXTRA_DIR%/include"
meson . build --prefix %EXTRA_DIR% --default-library static --buildtype release || exit /b 1
cd build
ninja || exit /b 1
ninja install || exit /b 1
cd ..\..
