bcc
===

Monkey-originated bcc parser for BlitzMax
Generates BlitzMax (mostly) compatible C-source which has the added advantage of being more portable than the original bcc-generated processor-specific assembler.


Building
--------

bcc is self-compiling and can be built using an existing version of BlitzMax:

First download an existing build of BlitzMax from https://blitzmax.org/downloads/

If you are on Linux please ensure you have the necessary dependencies installed: https://blitzmax.org/docs/en/setup/linux/

Clone/Download this repository and install dependencies:

	git submodule update --init

Using BlitzMax, compile `build.bmx` as a console application:

    bmk makeapp -r -t console build.bmx

Run `build`


When ran, build will prompt for your BlitzMax install path. You can alternatively pass this as a commandline parameter as so:

    build --bmx /path/to/bmx

To skip running tests and only build bcc, include the parameter `--build-only`

    build --bmx /path/to/bmx --build-only

Contributing
------------
To contribute a fix or feature, first add a test to `tests/` that fails (if a fix, the test should fail, highlighting the bug; If a feature the test should demonstrate how the new feature *will* work, but will obviously currently fail). Then make your additions, and build using `build`, ensuring all tests pass successfully.

Commit your change and issue a pull request.
