"
My subclasses describing a configuration/settings necessary to build some third-party library used by VM
or by one of it's plugins.

We cannot use cmake configuration for those libraries, since most of them having own 
configuration/make scripts which build that library.

I serve as a convenience layer for building those libraries and connecting them with cmake configuration,
as well as provide necessary information, what output file(s) should be bundled with virtual machine.

"
Class {
	#name : #CMThirdpartyLibrary,
	#superclass : #Object,
	#instVars : [
		'gen',
		'vmGen',
		'configurationFlags'
	],
	#category : #'CMakeVMMaker-Libs'
}

{ #category : #accessing }
CMThirdpartyLibrary class >> canonicalName [
	"answer the library canonical name, like 
		'freetype2'
		or 'cairo' 
		etc.
		
	Note , this method is used to find the corresponding library
	from all subclasses of CMThirdpartyLibrary	
	"
	^ self subclassResponsibility
]

{ #category : #'instance creation' }
CMThirdpartyLibrary class >> named: aName config: aCPlatformConfig [

	^ (self allSubclasses detect: [:cls | 
		cls canonicalName = aName and: [ cls supports: aCPlatformConfig ] ])
		new
]

{ #category : #accessing }
CMThirdpartyLibrary class >> platformName [ 
	^nil
]

{ #category : #testing }
CMThirdpartyLibrary class >> supports: aConfig [
	"default implementation"
	^ self platformName = aConfig platformName 
]

{ #category : #accessing }
CMThirdpartyLibrary >> archiveFileName [
	^ self downloadURL asUrl fileName 
]

{ #category : #'package properties' }
CMThirdpartyLibrary >> archiveMD5Sum [
	"answer the MD5 checksum (in string) for downloaded library archive 
	(to check that downloaded file is not corrupt).
	
	You can take this sum by issuing:
	  md5 filename
	from command line
	"
	^ self subclassResponsibility
]

{ #category : #'generating actions' }
CMThirdpartyLibrary >> build [

	self subclassResponsibility
]

{ #category : #'package properties' }
CMThirdpartyLibrary >> buildTarget [
	^ self canonicalName
]

{ #category : #'package properties' }
CMThirdpartyLibrary >> canonicalName [
	"answer the library canonical name, like 
		'freetype2'
		or 'cairo' 
		etc"
	^ self class canonicalName
]

{ #category : #settings }
CMThirdpartyLibrary >> configurationFlags [ 
	^(configurationFlags 
		ifNil: [ self defaultConfigurationFlags ])
		reduce: [ :a :b | a, ' ', b]
]

{ #category : #settings }
CMThirdpartyLibrary >> configurationFlags: aCollection [
	configurationFlags := aCollection
	
]

{ #category : #'generating actions' }
CMThirdpartyLibrary >> copy: src to: dest [

	| str |

	
	str := 'add_custom_command( OUTPUT "{2}"
	COMMAND cp "{1}" "{2}"
	DEPENDS "{1}"
	)' format: {src. dest }.
	
	gen puts: str
]

{ #category : #'generating actions' }
CMThirdpartyLibrary >> copyArtefacts [

	self subclassResponsibility
]

{ #category : #settings }
CMThirdpartyLibrary >> defaultConfigurationFlags [ 
	^#(
		'CFLAGS=''-arch i386'''
		'LDFLAGS=''-arch i386''')
]

{ #category : #'generating actions' }
CMThirdpartyLibrary >> defineAsTarget [

	self subclassResponsibility
]

{ #category : #'generating actions' }
CMThirdpartyLibrary >> defineGlobalTargets [
	self subclassResponsibility
]

{ #category : #'package properties' }
CMThirdpartyLibrary >> dependencies [
	^ #()
]

{ #category : #'generating actions' }
CMThirdpartyLibrary >> download [

	"Produce output to download library archive.
	By default, we use .tgz extension.. since it is most often used by OSS.
	Note, that we check if file is already present, to not download it every time
	we build"	
	
	gen puts:
'if (NOT EXISTS "${workDir}/${archiveFileName}")
	Message("Downloading  ',self fileServerURL,'${archiveFileName}")

	FILE(DOWNLOAD
		', self fileServerURL , self archiveFileName ,'
	 	"${workDir}/${archiveFileName}"
		STATUS downloadStatus
		SHOW_PROGRESS
	)
	
	LIST(GET downloadStatus 0 downloadError)
	if (NOT downloadError EQUAL 0)
		Message("File is missing on file server (', self fileServerURL,'), downloading from official repository...")
		FILE(DOWNLOAD
			${url}
		 	"${workDir}/${archiveFileName}"
			STATUS downloadStatus
			SHOW_PROGRESS
			EXPECTED_MD5 ${md5sum}
		)
		LIST(GET downloadStatus 0 downloadError)
	endif ()
	if (NOT downloadError EQUAL 0)
		message(FATAL_ERROR "Cannot find/download the source file from:" ${url})
	endif ()
		
	
endif ()
'
]

{ #category : #'package properties' }
CMThirdpartyLibrary >> downloadURL [
	"answer the url where given library can be downloaded from"
	^ self subclassResponsibility
]

{ #category : #settings }
CMThirdpartyLibrary >> fileServerURL [
	"Base url to file server where all external libs sources stored"
	^'http://files.pharo.org/vm/src/lib/'
]

{ #category : #'generating cmake file' }
CMThirdpartyLibrary >> generate [

	gen message: 'Configuring thirdparty package: ', self canonicalName.
	
	self 
		setVariables;
		download;
		unpack;
		build;
		copyArtefacts;
		defineAsTarget.
]

{ #category : #'generating cmake file' }
CMThirdpartyLibrary >> generateFor: aVMGenerator [

	| libDir stream contents |
	
	vmGen := aVMGenerator.
	
	gen := CMakeGenerator new
		output: (String new writeStream).
	
	libDir := (aVMGenerator thirdpartyDir / self canonicalName) ensureDirectory.

	stream := String new writeStream.
	
	self generate.

	stream nextPutAll: (vmGen config fixLineEndsOf: gen output contents).

	contents := stream contents. 
	
	(self isFile: (libDir asFileReference / gen outputFileName) fullName hasContents: contents) ifFalse: [
		"contents changed, update the file. Because fucking cmake will force rebuild everything if we change its modification date
		without changing its contents"
		(FileStream forceNewFileNamed: (libDir asFileReference / gen outputFileName)) nextPutAll: contents; close.
		].
	

	vmGen addSubdirectory:  vmGen thirdpartyDirName , '/' , self canonicalName.
	self defineGlobalTargets.
	
]

{ #category : #'generating cmake file' }
CMThirdpartyLibrary >> isFile: aFileName hasContents: aString [

	| newContents old |
	
	newContents := false.
	
	old := FileStream oldFileOrNoneNamed: aFileName.
	
	old ifNil: [ ^ false ].
	
	^ [ old contents = aString ] ensure: [ old close ]
]

{ #category : #'package properties' }
CMThirdpartyLibrary >> libraryFileName [
	"answer the built library file name"

	self subclassResponsibility
]

{ #category : #'generating actions' }
CMThirdpartyLibrary >> setVariables [

	gen
		set: #libName toString: self canonicalName;
		set: #workDir toString: '${thirdpartyDir}/${libName}';
		set: #unpackedDirName toString: self unpackedDirName;
		set: #libSourcesDir toString: '${workDir}/${unpackedDirName}';
		set: #url toString: self downloadURL;
		set: #md5sum toString: self archiveMD5Sum;
		set: #archiveFileName toString: self archiveFileName;
		set: #installPrefix toString: '${thirdpartyDir}/out'.
]

{ #category : #exports }
CMThirdpartyLibrary >> targetForLinking [
	"Answer a target or path to library to link with, which can be used by 
	external plugins or VM module"

	^ '${externalModulesDir}/', self libraryFileName
]

{ #category : #'generating actions' }
CMThirdpartyLibrary >> unpack [
	"produce commands for unpacking the library archive.
	
	the output of this command should use a directory
	${workDir}/${libName}
	where the unpacked library sources will be located.
	
	see #setVariables method for understanding what variables used here
	"

	gen set: #unpackTarget toString: '${libSourcesDir}/touch.cmake'.
	
	gen puts:
'add_custom_command(OUTPUT "${unpackTarget}"
		COMMAND tar -xzf "${archiveFileName}" 
		COMMAND touch "${unpackTarget}"
		COMMENT "Unpacking ${libName} ... "
	)
'.

]

{ #category : #'package properties' }
CMThirdpartyLibrary >> unpackedDirName [
	"answer the directory name, which is created after unpacking
	downloaded archive i.e.
	
	the archive downloaded from 
	
	http://ftp.igh.cnrs.fr/pub/nongnu/freetype/freetype-2.4.9.tar.gz
	
	if untarred, will create
	freetype-2.4.9
	subdirectory. But since there is no conventions, it could be anything,
	so we should specify it here, so build system will know where to look for unpacked files"

	^ self subclassResponsibility
]
