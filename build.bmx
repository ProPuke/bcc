SuperStrict

Framework brl.standardio

Import pub.freeprocess
Import "tools/SimpleCodeTester/app.testmanager.bmx"

Enum EMode
	DebugMode
	ReleaseMode
End Enum

Const testPath$ = ".test"

Global bmxPath$
Global clear% = False
Global verbose% = False
Global enableBuild% = True
Global enableTests% = True
Global mode:EMode = EMode.ReleaseMode

Local i% = 1
While i < Appargs.Length
	Local arg$ = Appargs[i]
	Select arg
		Case "-c", "--clean"
			CleanFiles
			End

		Case "-d", "--debug"
			mode = EMode.DebugMode

		Case "-r", "--release"
			mode = EMode.ReleaseMode

		Case "-v", "--verbose"
			verbose = True

		Case "-h", "--help"
			PrintHelp
			End

		Case "-b", "--build-only"
			enableBuild = True
			enableTests = False

		Case "-t", "--test-only"
			enableBuild = False
			enableTests = True

		Case "--bmx"
			i :+ 1
			If i >= AppArgs.Length
				PrintHelp
				End
			End If
			bmxPath = Appargs[i]
	End Select

	i :+ 1
End While

Function PrintHelp()
	Print "Usage: " + Appargs[0] + " [OPTION]..."
	Print "Builds bcc from source and runs tests"
	Print
	Print "Arguments:"
	Print
	Print "  --bmx <path>      Specify bmx path"
	Print "  -d, --debug       Use debug mode"
	Print "  -r, --release     Use release mode (default)"
	Print "  -v, --verbose     Run commands verbosely"
	Print "  -h, --help        Display this message"
	Print "  -c, --clean       Clean existing files and exit"
	Print "  -b, --build-only  Build bcc only (do not run tests)"
	Print "  -t, --test-only   Run tests only (do not rebuild bcc)"
	Print
End Function

Function QuoteCommandline$(a$)
	If a.Length < 1 Return "" 'empty
	If a[0] = "~q" Return a 'already quoted

	If a.Find(" ")=-1 Return a	'no spaces

	Return "~q"+a+"~q"
End Function

Function RunProcess$(isExecutable:Int, executable$, arguments$[] = [])
	if isExecutable
		?Win32
			executable :+ ".exe"
		?

		If Not FileType(executable)
			Print "ERROR: Program not found: "+executable
			Return ""
		End If
	End If

	Local commandline$ = QuoteCommandline(executable)+" "+" ".Join(arguments)

	Local process:TProcess = CreateProcess(commandline, HIDECONSOLE)

	If Not Process
		Print "ERROR: Program not found: "+executable
		Return ""
	End If

	If verbose Then Print "> "+commandline

	Local output$
	Local error$
	Local bytes:Byte[]

	Repeat
		Delay 50
		bytes = process.pipe.ReadPipe()
		If bytes
			Local data$ = String.FromBytes(bytes, bytes.length)
			output :+ data
			StandardIOStream.WriteString data
			StandardIOStream.Flush
		EndIf
		bytes = process.err.ReadPipe()
		If bytes
			Local data$ = String.FromBytes(bytes, bytes.length)
			error :+ data
			StandardIOStream.WriteString data
			StandardIOStream.Flush
		EndIf
	Until Not process.status()

	process.Close()

	If output Or error Then Print

	If error Then Return ""

	Return output.Trim().Replace("~r","")
End Function

Function BuildBcc%()
	Print
	Print "Building bcc..."
	Print

	Local bmkArguments:String[] = ["makeapp", "-a"]

	Select mode
		Case EMode.DebugMode
			bmkArguments = bmkArguments[..bmkArguments.Length+3]
			bmkArguments[bmkArguments.Length-3] = "-d"
			bmkArguments[bmkArguments.Length-2] = "-o"
			bmkArguments[bmkArguments.Length-1] = "bcc.debug"
			
		Case EMode.ReleaseMode
			bmkArguments = bmkArguments[..bmkArguments.Length+3]
			bmkArguments[bmkArguments.Length-3] = "-r"
			bmkArguments[bmkArguments.Length-2] = "-o"
			bmkArguments[bmkArguments.Length-1] = "bcc"
	End Select

	bmkArguments = bmkArguments[..bmkArguments.Length+1]
	bmkArguments[bmkArguments.Length-1] = "bcc.bmx"

	IF Not RunProcess(True, bmxPath+"/bin/bmk", bmkArguments) Then Return False

	Print "Build complete"
	Return True
End Function

Function CleanFiles%()
	Local dirs:String[] = [""]
	Local files:String[] = ["bcc[EXECUTABLE]", "bcc.debug[EXECUTABLE]", "tools/SimpleCodeTester/sct[EXECUTABLE]"]

	Print
	Print "Cleaning files..."
	Print

	?Win32
		Local executableExtension$ = ".exe"
	?Not Win32
		Local executableExtension$ = ""
	?

	For Local dir:String = EachIn dirs
		If Not DeleteDir(testPath+dir, True)
			Print "ERROR: Unable to delete "+testPath+dir
			Return False
		End If
	Next
	
	For Local file:String = EachIn files
		file = file.Replace("[EXECUTABLE]", executableExtension)
		If Not DeleteFile(testPath+file) AND FileType(testPath+file)
			Print "ERROR: Unable to delete "+testPath+file
			Return False
		End If
	Next

	Print "All files cleaned"
	Return True
End Function

Function CreateTestEnvironment%(testPath:String)
	Local makeDirs:String[] = ["/mod", "/bin"]
	Local copyDirs:String[] = []
	Local copyFiles:String[] = ["/bin/core.bmk", "/bin/make.bmk", "/bin/bmk[EXECUTABLE]"]
	Local runCommands:String[][] = []

	?Win32
		If FileType(bmxPath+"/MinGW32x86")
			copyDirs = copyDirs[..copyDirs.Length+1]
			copyDirs[copyDirs.Length-1] = "/MinGW32x86"
		End If
		If FileType(bmxPath+"/MinGW32x64")
			copyDirs = copyDirs[..copyDirs.Length+1]
			copyDirs[copyDirs.Length-1] = "/MinGW32x64"
		End If
	?

	If Not FileType(testPath+"/mod/pub.mod")
		runCommands = runCommands[..runCommands.Length+1]
		runCommands[runCommands.Length-1] = ["CLONE  /mod/pub.mod/", "git", "clone", "--depth", "1", "https://github.com/bmx-ng/pub.mod.git", testPath+"/mod/pub.mod"]
	End If

	If Not FileType(testPath+"/mod/brl.mod")
		runCommands = runCommands[..runCommands.Length+1]
		runCommands[runCommands.Length-1] = ["CLONE  /mod/brl.mod/", "git", "clone", "--depth", "1", "https://github.com/bmx-ng/brl.mod.git", testPath+"/mod/brl.mod"]
	End If

	If Not FileType(testPath)
		If Not CreateDir(testPath) Then Return False
	End If

	For Local path:String = EachIn makeDirs
		If FileType(testPath+path) Then Continue

		Print "  CREATE "+path+"/"
		If Not CreateDir(testPath+path) Then Return False
	Next

	For Local path:String = EachIn copyDirs
		If FileType(testPath+path) Then Continue

		Print "  COPY   "+path+"/*"
		If Not CopyDir(bmxPath+path, testPath+path) Then Return False
	Next

	?Win32
		Local executableExtension$ = ".exe"
	?Not Win32
		Local executableExtension$ = ""
	?

	For Local file:String = EachIn copyFiles
		file = file.Replace("[EXECUTABLE]", executableExtension)
		If FileType(testPath+file) Then Continue

		Print "  COPY   "+file
		If Not CopyFile(bmxPath+file, testPath+file) Then Return False
	Next

	For Local command:String[] = EachIn runCommands
		Print "  "+command[0]
		RunProcess(False, command[1], command[2..])
	Next

	Local scopeDir:Byte Ptr = ReadDir(testPath+"/mod")
	If scopeDir
		Local scope$ = NextFile(scopeDir)
		While scope
			If scope[0] <> ASC(".")
				Local scopePath$ = "/mod/"+scope
				If FileType(testPath+scopePath) = FILETYPE_DIR
					Local nameDir:Byte Ptr = ReadDir(testPath+scopePath)
					Local name$ = NextFile(nameDir)
					While name
						If name[0] <> ASC(".")
							Local namePath$ = scopePath+"/"+name
							If FileType(testPath+namePath) = FILETYPE_DIR And FileType(testPath+namePath+"/.bmx") = FILETYPE_DIR
								Print "  DELETE "+namePath+"/.bmx"
								If Not DeleteDir(testPath+namePath+"/.bmx", True) Then Return False
							End If
						End If
						name = NextFile(nameDir)
					End While
				End If
			End If

			scope = NextFile(scopeDir)
		End While
	End If

	Local localEnding$ = ""

	Select mode
		Case EMode.DebugMode
			localEnding = ".debug"
			
		Case EMode.ReleaseMode
	End Select

	Print "  COPY   /bin/bcc"+executableExtension
	If Not CopyFile("bcc"+localEnding+executableExtension, testPath+"/bin/bcc"+executableExtension) Then Return False

	Return True
End Function

Function RunTests%()
	Print
	Print "Creating test environment..."
	Print

	If Not CreateTestEnvironment(testPath)
		Print
		Print "ERROR: An error occured creating test environment"
		Return False
	End If

	' Local sctPath$ = "tools/SimpleCodeTester/sct"
	Local bmkPath$ = "../"+testPath+"/bin/bmk"

	?Win32
		' sctPath :+ ".exe"
		bmkPath :+ ".exe"
	?

	' If Not FileType(sctPath)
	' 	Print "SimpleCodeTester is not built. Building..."
	' 	Print
	' 	If Not RunProcess(True, bmxPath+"/bin/bmk", ["makeapp", "-a", "-r", sctPath+".bmx"])
	' 		Print "ERROR: SimpleCodeTester not found and unable to build it"
	' 		Return False
	' 	End If
	' End If

	Print
	Print "Running tests..."
	Print

	'run sct internally, so we can manually set bmk_path correctly
	TTestCompiler.baseConfig.Add("bmk_path", bmkPath)
	
	TTestCompiler.baseConfig.Add("threadedTestRuns", "0")
	TTestCompiler.baseConfig.Add("app_type", "console")
	TTestCompiler.baseConfig.Add("app_arch", "") 'use the default local arch
	TTestCompiler.baseConfig.Add("debug", "0")
	TTestCompiler.baseConfig.Add("threaded", "0")
	TTestCompiler.baseConfig.Add("deleteBinaries", "1") 'delete binaries afterwards
	TTestCompiler.baseConfig.Add("make_mods", "0")
	TTestCompiler.baseConfig.Add("quick", "0")
	TTestCompiler.baseConfig.fileUri = ""
	
	Global testManager:TTestManager = New TTestManager.Init(["tests"])
	testManager.RunTests()
	Print

	' Local result$ = RunProcess(True, sctPath, ["../../tests"])
	' If Not result Then Return False

	Local problems% = testManager.GetResultCount(TTestBase.RESULT_FAILED)+testManager.GetResultCount(TTestBase.RESULT_ERROR)

	If problems>0
		Print "ERROR: "+problems+" problems encountered during tests"
		Return False
	End If

	Print "All tests complete"
	Return True
End Function

If Not bmxPath
	bmxPath = Input("Please specify bmx path> ")
	If Not bmxPath Then End
	Print
End If

If enableBuild And Not BuildBcc() Then End
If enableTests And Not RunTests() Then End
