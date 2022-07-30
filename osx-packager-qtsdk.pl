#!/usr/bin/perl

### = file
### osx-packager-qtsdk.pl
###
### = revision
### 3.0
###
### Copyright (c) 2016-2018 Piotr Oniszczuk
### Copyright (c) 2012-2014 Jean-Yves Avenard
### based on osx-packager.pl by by Jeremiah Morris <jm@whpress.com>
###
### = location
### https://github.com/MythTV/packaging//OSX/build/osx-packager-qtsdk.pl
###
### = description
### Tool for automating frontend builds on Mac OS X.
### Run "osx-packager-qtsdk.pl -man" for full documentation.

use strict;
use Getopt::Long qw(:config auto_abbrev);
use Pod::Usage ();
use Cwd ();
use File::Temp qw/ tempfile tempdir /;

### Configuration settings (stuff that might change more often)

# We try to auto-locate the Git client binaries.
# If they are not in your path, we build them from source
#
our $git = `which git`; chomp $git;

# try to locate if ccache exists
our $ccache = `which ccache`; chomp $ccache;


# This script used to always delete the installed include and lib dirs.
# That probably ensures a safe build, but when rebuilding adds minutes to
# the total build time, and prevents us skipping some parts of a full build
#
our $cleanLibs = 1;

# By default, only the frontend is built (i.e. no backend or transcoding)
#
our $backend = 0;
our $jobtools = 0;

# Start with a generic address and let sourceforge
# figure out which mirror is closest to us.
#
our $sourceforge = 'http://downloads.sourceforge.net';

# At the moment, there is mythtv plus...
our @components = ( 'mythplugins' );
#our @components = ('');

# The OS X programs that we are likely to be interested in.
our @targets   = ( 'MythFrontend',  'MythWelcome' );
our @targetsJT = ( 'MythCommFlag', 'MythJobQueue');
our @targetsBE = ( 'MythBackend',  'MythFillDatabase', 'MythTV-Setup');

# Name of the PlugIns directory in the application bundle
our $BundlePlugins = "PlugIns";
our $OSTARGET = "10.9";
our $PYVER = "2.7";
our $PYTHON = "python$PYVER";

# Patches for MythTV source
our %patches = ();

our %build_profile = (
  'master'
   => [
    'branch' => 'master',
    'mythtv'
    => [
        'ccache',
        'libtool',
        'pkgconfig',
        'dvdcss',
        'freetype',
        'lame',
        'cmake',
        'ncurses',
        'mysqlclient',
        #'dbus',
        'qtsqldriver',
        #'qtwebkit',
        'yasm',
        'liberation-sans',
        'libtool',
        'autoconf',
        'automake',
        'taglib',
        'exiv2',
        'ninja',
        'soundtouch',
        'libsamplerate',
        'libxml2',
        'libbluray',
        'lzo',
        'libzip',
        'openssl',
        'python-mysql',
        'python-lxml',
        'python-pycurl-old',
        'python-urlgrabber',
        'python-simplejson',
        'python-oauth',
        #'python-requests',
        #'python-certifi',
        #'python-urllib3',
        #'python-idna',
        #'python-chardet',
        #'python-pyOpenSSL',
        #'python-six',
        #'python-pyasn1',
        #'python-enum34',
        #'python-ipaddress',
        #'python-ordereddict',
        #'python-pycparser',
        #'python-cffi',
       ],
    'mythplugins'
    => [
        'exif',
# MythMusic needs these:
        'libtool',
        'autoconf',
        'automake',
        'libogg',
        'vorbis',
        'flac',
        'libcddb',
        'libcdio',
       ],
     ],
  '29-fixes'
  => [
    'branch' => 'fixes/29',
    'mythtv'
    =>  [
        'ccache',
        'libtool',
        'pkgconfig',
        'dvdcss',
        'freetype',
        'lame',
        'cmake',
        'mysqlclient',
        #'dbus',
        'qt',
        'yasm',
        'liberation-sans',
        'firewiresdk',
        'libtool',
        'autoconf',
        'automake',
        'taglib',
        'exiv2',
        'python-mysql',
        'python-lxml',
        'openssl',
        'python-pycurl',
        'python-urlgrabber',
        'python-simplejson',
      ],
    'mythplugins'
    =>  [
        'exif',
# MythMusic needs these:
        'libtool',
        'autoconf',
        'automake',
        'libogg',
        'vorbis',
        'flac',
        'libcddb',
        'libcdio',
      ],
    ],
);

=head1 NAME

osx-packager.pl - build OS X binary packages for MythTV

=head1 SYNOPSIS

 osx-packager.pl [options]

 Options:
  -help              print the usage message
  -man               print full documentation
  -verbose           print informative messages during the process
  -distclean         throw away all myth installed and intermediates
                     files and exit
  -qtsdk <path>      path to Qt SDK Deskop
                     (e.g. -qtsdk ~/QtSDK/Desktop/Qt/4.8.0
  -qtbin <path>      path to Qt utilitities (qmake etc)
  -qtplugins <path>  path to Qt plugins
  -gitrev <str>      build a specified Git revision or tag

 You must provide either -qtsdk or -qtbin *and * -qtplugins

 Advanced Options:
  -gitdir    <path>  build using provided myth git cloned directory
  -srcdir    <path>  build using provided root source directory
  -pkgsrcdir <path>  build using provided packaging directory
  -archive   <path>  specify where dependencies archives can be found
                     (default is .osx-packager/src)
  -force             use myth source directory as-is,
                     with no GIT validity check
  -nodistclean       do not perform a distclean prior to building myth
  -thirdclean        do a clean rebuild of third party packages
  -thirdskip         don't rebuild the third party packages
  -mythtvskip        don't rebuild/install mythtv, requires -nodistclean
  -pluginskip        don't rebuild/install mythplugins
  -nohead            don't update to HEAD revision of MythTV before
                     building
  -clean             clean myth module before rebuilding it (default)
  -noclean           use with -nohead, do not re-run configure nor clean
  -usehdimage        perform build inside of a case-sensitive disk image
  -leavehdimage      leave disk image mounted on exit
  -enable-backend    build the backend server as well as the frontend
  -enable-jobtools   build commflag/jobqueue  as well as the frontend
  -profile           build with compile-type=profile
  -debug             build with compile-type=debug
  -plugins <str>     comma-separated list of plugins to include
  -noparallel        do not use parallel builds.
                     compiling Qt from source will fail will parallel builds
  -nobundle          only recompile, do not create application bundle
  -bootstrap         exit after building all thirdparty components
  -nosysroot         compiling with sysroot only works with 0.25 or later
                     use -nosysroot if compiling earlier version
  -olevel <n>        compile with extra -On
  -buildprofile <x>  build either master or fixes-29 (default: master)
  -gcc               build using gcc (deprecated, default is clang/clang++)
  -no-optimization   build mythtv without compiler optimization
                     Useful for debugging
  -enable-mythlogserver Enable mythlogserver (required for building myth <= 0.26)


=head1 DESCRIPTION

This script builds a MythTV frontend and all necessary dependencies, along
with plugins as specified, as a standalone binary package for Mac OS X.

It is designed for building daily Git snapshots,
and can also be used to create release builds with the '-gitrev' option.

All intermediate files go into an '.osx-packager' directory in the current
working directory. The finished application is named 'MythFrontend.app' and
placed in the current working directory.
 
=head1 REQUIREMENTS
 
You need to have installed either Qt SDK (64 bits only) or
Qt libraries package (both 32 and 64 bits) from http://qt.nokia.com/downloads.
 
When using the Qt SDK, use the -qtsdk flag to define the location of the Desktop Qt,
by default it is ~/QtSDK/Desktop/Qt/[VERSION]/gcc where version is 4.8.0 (SDK 1.2)
or 473 (SDK 1.1)

When using the Qt libraries package, use the -qtbin and -qtplugins. Values for default
Qt installation are: -qtbin /usr/bin -qtplugins /Developer/Applications/Qt/plugins.
Qt Headers must be installed.

=head1 EXAMPLES

Building two snapshots, one with all plugins and one without:

  osx-packager.pl -qtbin /usr/bin -qtplugins /Developer/Applications/Qt/plugins
  mv MythFrontend.app MythFrontend-plugins.app 
  osx-packager.pl -nohead -pluginskip -qtbin /usr/bin -qtplugins /Developer/Applications/Qt/plugins
  mv MythFrontend.app MythFrontend-noplugins.app

Building a "fixes" branch:

  osx-packager.pl -gitrev fixes/0.24 -qtsrc 4.6.4 -nosysroot -m32

Note that this script will not build old branches.
Please try the branched version instead. e.g.
http://svn.mythtv.org/svn/branches/release-0-21-fixes/mythtv/contrib/OSX/osx-packager.pl

=head1 CREDITS

Written by Jean-Yves Avenard <jyavenard@gmail.com>
Based on work by Jeremiah Morris <jm@whpress.com>

Includes contributions from Nigel Pearson, Jan Ornstedt, Angel Li, and Andre Pang, Bas Hulsken (bhulsken@hotmail.com)

=cut

# Parse options
our (%OPT);
Getopt::Long::GetOptions(\%OPT,
                         'help|?',
                         'man',
                         'verbose',
                         'distclean',
                         'thirdclean',
                         'nodistclean',
                         'noclean',
                         'thirdskip',
                         'mythtvskip',
                         'pluginskip',
                         'gitrev=s',
                         'nohead',
                         'usehdimage',
                         'leavehdimage',
                         'enable-backend',
                         'enable-jobtools',
                         'profile',
                         'debug',
                         'plugins=s',
                         'gitdir=s',
                         'srcdir=s',
                         'pkgsrcdir=s',
                         'force',
                         'archives=s',
                         'buildprofile=s',
                         'bootstrap',
                         'nohacks',
                         'noparallel',
                         'qtsdk=s',
                         'qtbin=s',
                         'qtplugins=s',
                         'nobundle',
                         'olevel=s',
                         'nosysroot',
                         'gcc',
                         'no-optimization',
                         'enable-mythlogserver',
                         'disable-checks',
                        ) or Pod::Usage::pod2usage(2);
Pod::Usage::pod2usage(1) if $OPT{'help'};
Pod::Usage::pod2usage('-verbose' => 2) if $OPT{'man'};

if ( $OPT{'enable-backend'} )
{   $backend = 1  }

if ( $OPT{'noclean'} )
{   $cleanLibs = 0  }

if ( $OPT{'enable-jobtools'} )
{   $jobtools = 1  }

if ( $OPT{'srcdir'} )
{
    $OPT{'nohead'} = 1;
    $OPT{'gitrev'} = '';
}

# Build our temp directories
our $SCRIPTDIR = Cwd::abs_path(Cwd::getcwd());
if ( $SCRIPTDIR =~ /\s/ )
{
    &Complain(<<END);
Working directory contains spaces

Error: Your current working path:

   $SCRIPTDIR

contains one or more spaces. This will break the compilation process,
so the script cannot continue. Please re-run this script from a different
directory (such as /tmp).

The application produced will run from any directory, the no-spaces
rule is only for the build process itself.

END
    die;
}

our $WORKDIR = "$SCRIPTDIR/.osx-packager";
mkdir $WORKDIR;

if ($OPT{usehdimage})
{   MountHDImage()   }

our $PREFIX = "$WORKDIR/build";
mkdir $PREFIX;

our $SRCDIR = "$WORKDIR/src";
mkdir $SRCDIR;

our $ARCHIVEDIR ='';
if ( $OPT{'archives'} )
{
    $ARCHIVEDIR = "${SCRIPTDIR}/$OPT{'archives'}";
} else {
    $ARCHIVEDIR = "$SRCDIR";
}

our $QTSDK = "";
our $QTBIN = "";
our $QTLIB = "";
our $QTPLUGINS = "";
our $QTVERSION = "";
our $GITVERSION = "";

if ( $OPT{'qtsdk'} )
{
    $QTSDK = $OPT{'qtsdk'};
}

if ( $OPT{'qtbin'} )
{
    $QTBIN = "$OPT{'qtbin'}";
}
elsif ( $OPT{'qtsdk'} )
{
    $QTBIN = "$OPT{'qtsdk'}/bin";
}
if ( $OPT{'qtplugins'} )
{
    $QTPLUGINS = "$OPT{'qtplugins'}";
}
elsif ( $OPT{'qtsdk'} )
{
    $QTPLUGINS = "$QTSDK/plugins";
}

# Test if Qt conf is valid, all paths must exist
if ( ! ( (($QTBIN ne "") && ($QTPLUGINS ne "")) &&
     ( -d $QTBIN && -d $QTPLUGINS )) )
{
    &Complain("bin:$QTBIN lib:$QTLIB plugins:$QTPLUGINS You must define a valid Qt SDK path with -qtsdk <path> or -qtbin <path> *and* -qtplugins <path>");
    exit;
}

#Determine the version Qt SDK we are using, we need to retrieve the source code to build MySQL Qt plugin
if ( ! -e "$QTBIN/qmake" )
{
    &Complain("$QTBIN isn't a valid Qt bin path (qmake not found)");
    exit;
}
my @ret = `$QTBIN/qmake --version`;
my $regexp = qr/Qt version (\d+\.\d+\.\d+) in (.*)$/;
foreach my $line (@ret)
{
    chomp $line;
    next if ($line !~ m/$regexp/);
    $QTVERSION = $1;
    $QTLIB = $2;
    &Verbose("Qt version is $QTVERSION");
}

if ($QTVERSION eq "")
{
    &Complain("Couldn't identify Qt version");
    exit;
}
if ( ! -d $QTLIB )
{
    &Complain("$QTLIB doesn't exist. Invalid Qt sdk");
    exit;
}

our %depend_order = '';
my $gitrevision = 'master';  # Default thingy to checkout
if ( $OPT{'buildprofile'} == '29-fixes' )
{
    &Verbose('Building using 29-fixes profile');
    %depend_order = @{ $build_profile{'29-fixes'} };
    $gitrevision = 'fixes/29'
}
else
{
    &Verbose('Building using master profile');
    %depend_order = @{ $build_profile{'master'} };
}

our $GITDIR = "$SRCDIR/myth-git";
if ( $OPT{'gitdir'} )
{
    if ( ! -d "$OPT{'gitdir'}/.git" )
    {
        &Complain("$OPT{'gitdir'} isn't a valid git directory");
        exit;
    }
    $GITDIR = $OPT{'gitdir'};
}

our @pluginConf;
if ( $OPT{plugins} )
{
    @pluginConf = split /,/, $OPT{plugins};
    @pluginConf = grep(s/^/--enable-/, @pluginConf);
    unshift @pluginConf, '--disable-all';
}
else
{
    @pluginConf = (
        '--enable-opengl',
        '--enable-exif',
        '--enable-new-exif',
        '--enable-mythzoneminder',
        '--enable-mythmusic',
        '--enable-mythbrowser',
        '--enable-mythnews',
    );
}

# configure mythplugins, and mythtv, etc
our %conf = (
  'mythplugins'
  =>  [
        @pluginConf
      ],
  'mythtv'
  =>  [
        '--runprefix=../Resources',
        '--enable-libmp3lame',
        '--disable-lirc',
        '--disable-distcc',
        '--disable-firewire',
        "--python=/usr/bin/$PYTHON",
      ],
);

# configure mythplugins, and mythtv, etc
our %makecleanopt = (
  'mythplugins'
  =>  [
        'distclean',
      ],
);

use File::Basename;
our $gitpath = dirname $git;
our $ccachepath = dirname $ccache;

# Clean the environment
$ENV{'PATH'} = "$PREFIX/bin:/bin:/usr/bin:/usr/sbin:$gitpath:$ccachepath";
$ENV{'PKG_CONFIG_PATH'} = "$PREFIX/lib/pkgconfig:";
delete $ENV{'CPP'};
delete $ENV{'CXX'};

# Make needed symlinks for macos openssl
&Syscall("mkdir -p $PREFIX/lib") or die;
&Syscall("ln -sf /usr/lib/libcrypto.35.dylib $PREFIX/lib/libcrypto.1.0.0.dylib") or die;
&Syscall("ln -sf /usr/lib/libcrypto.35.dylib $PREFIX/lib/libcrypto.dylib") or die;

our $DEVROOT = `xcode-select -print-path`; chomp $DEVROOT;
our $SDKNAME = `xcodebuild -showsdks | grep macosx11 | sort | head -n 1 | awk '{ print \$NF }' `; chomp $SDKNAME;
our $SDKVER = $SDKNAME; $SDKVER =~ s/macosx//g;
our $SDKROOT = "$DEVROOT/SDKs/MacOSX$SDKVER.sdk";

$ENV{'DEVROOT'} = $DEVROOT;
$ENV{'SDKVER'} = $SDKVER;
$ENV{'SDKROOT'} = $SDKROOT;
$ENV{'DYLD_LIBRARY_PATH'} = "$PREFIX/lib";
$ENV{'PYTHONPATH'} = "$PREFIX/lib/$PYTHON/site-packages";

our $GCC = $OPT{'gcc'};
our $CCBIN;
our $CXXBIN;
# Determine appropriate gcc/g++ path for the selected SDKs
if ($GCC)
{
    $CCBIN = `xcodebuild -find gcc -sdk $SDKNAME`; chomp $CCBIN;
    $CXXBIN = `xcodebuild -find g++ -sdk $SDKNAME`; chomp $CXXBIN;
    my $XCODEVER = `xcodebuild -version`; chomp $XCODEVER;
    if ( $XCODEVER =~ m/Xcode\s+(\d+\.\d+(\.\d+)?)/ && ! $OPT{'olevel'} )
    {
        if ( $1 =~ m/^4\.2/ )
        {
            &Complain("XCode 4.2 is buggy, please upgrade to 4.3 or later");
        }
    }
    # Test if llvm-gcc, mythtv doesn't compile unless you build in debug mode
    my $out = `$CCBIN --version`;
    if ( $out =~ m/llvm-gcc/ )
    {
        $OPT{'debug'} = 1;
        &Verbose('Using llvm-gcc: Forcing debug compile...');
    }
}
else
{
    $CCBIN = `xcodebuild -find clang -sdk $SDKNAME`; chomp $CCBIN;
    $CXXBIN = `xcodebuild -find clang++ -sdk $SDKNAME`; chomp $CXXBIN;
}

$ENV{'CC'} = $CCBIN;
$ENV{'CXX'} = $CXXBIN;
$ENV{'CPP'} = "$CCBIN -E";
$ENV{'CXXCPP'} = "$CXXBIN -E";

if ( ! -e "$SDKROOT" && ! $OPT{'nosysroot'} )
{
    #Handle special case for 10.4 where the SDK name is 10.4u.sdk
    $SDKROOT = "$DEVROOT/SDKs/MacOSX${SDKVER}u.sdk";
    if ( ! -e "$SDKROOT" )
    {
        # Handle XCode 4.3 new location
        $SDKROOT = "$DEVROOT/Platforms/MacOSX.platform/Developer/SDKs/MacOSX$SDKVER.sdk";
        if ( ! -e "$SDKROOT" )
        {
            &Complain("$SDKROOT doesn't exist");
            &Complain("Did you set your xcode environmment path properly ? (xcode-select utility)");
            exit;
        }
    }
}

#Compilation was broken when using sysroots, mythtv code was fixed from 0.25 only. so this makes it configurable
our $SDKISYSROOT = "-isysroot $SDKROOT";
our $SDKLSYSROOT = "-Wl,-syslibroot,${SDKROOT}";
if ( $OPT{'nosysroot'} )
{
    $SDKISYSROOT = "";
    $SDKLSYSROOT = "";
}

# set up Qt environment
$ENV{'QTDIR'} = "$QTSDK";
if ($GCC)
{
    $ENV{'QMAKESPEC'} = 'macx-g++';
}
else
{
    $ENV{'QMAKESPEC'} = 'macx-clang';
}

# Can't set this if we want python to work
#$ENV{'MACOSX_DEPLOYMENT_TARGET'} = $OSTARGET;

our $OLEVEL="";
if ( $OPT{'olevel'} =~ /^\d+$/ )
{
    $OLEVEL="-O" . $OPT{'olevel'} . " ";
}

my $SDK105FLAGS="";
if ( $SDKVER =~ m/^10\.[3-5]/ )
{
    $SDK105FLAGS = " -D_USING_105SDK=1";
}

my $ECFLAGS = "";

$ENV{'CFLAGS'} = $ENV{'CXXFLAGS'} = $ENV{'ECXXFLAGS'} = $ENV{'CPPFLAGS'} = "${OLEVEL}${SDKISYSROOT}${SDK105FLAGS} -mmacosx-version-min=$OSTARGET -I$PREFIX/include -I$PREFIX/mysql ";
$ENV{'LDFLAGS'} = "$SDKLSYSROOT -mmacosx-version-min=$OSTARGET -L$PREFIX/lib -F$QTLIB";
$ENV{'PREFIX'} = $PREFIX;
$ENV{'SDKROOT'} = $SDKROOT;

if ( $OPT{'qtbin'} )
{
    $ENV{'ECXXFLAGS'} .= " -F$QTLIB";
}

# compilation flags used for compiling dependency tools, do not use multi-architecture
our $CFLAGS    = $ENV{'CFLAGS'};
our $CXXFLAGS  = $ENV{'CXXFLAGS'};
our $ECXXFLAGS = $ENV{'ECXXFLAGS'};
our $CPPFLAGS  = $ENV{'CPPFLAGS'};
our $LDFLAGS   = $ENV{'LDFLAGS'};
our $ARCHARG   = "";
our @ARCHS;

# Check host computer architecture and create list of architecture to build
my $arch = `sysctl -n hw.machine`; chomp $arch;
push @ARCHS, $arch;

# Test if Qt libraries support required architectures. We do so by generating a dummy project and trying to compile it
&Verbose("Testing Qt environment");
my $dir = tempdir( CLEANUP => 1 );
my $tmpe = "$dir/test";
my $tmpcpp = "$dir/test.cpp";
my $tmppro = "$dir/test.pro";
my $make = "$dir/Makefile";
open fdcpp, ">", $tmpcpp;
print fdcpp "#include <QString>\nint main(void) { QString(); }\n";
close fdcpp;
open fdpro, ">", $tmppro;
my $name = basename($tmpe);
print fdpro "SOURCES=$tmpcpp\nTARGET=$name\nDESTDIR=$dir\nCONFIG-=app_bundle";
close fdpro;
my $cmd = "$QTBIN/qmake \"QMAKE_CC=$CCBIN\" \"QMAKE_CXX=$CXXBIN\" \"QMAKE_CXXFLAGS=$ENV{'ECXXFLAGS'}\" \"QMAKE_CFLAGS=$ENV{'CFLAGS'}\" \"QMAKE_LFLAGS+='$ENV{'LDFLAGS'}'\" -o $make $tmppro";
$cmd .= " 2> /dev/null > /dev/null" if ( ! $OPT{'verbose'} );
&Syscall($cmd);
&Syscall(['/bin/rm' , '-f', $tmpe]);
$cmd = "/usr/bin/make -C $dir -f $make $name";
$cmd .= " 2>/dev/null >/dev/null" if ( ! $OPT{'verbose'} );
my $result = &Syscall($cmd);

if ( $result ne "1" )
{
    &Complain("Couldn't use Qt for the architectures @ARCHS.");
    exit;
}

# show summary of build parameters.
&Verbose("DEVROOT = $DEVROOT");
&Verbose("SDKVER = $SDKVER");
&Verbose("SDKROOT = $SDKROOT");
&Verbose("CCBIN = $ENV{'CC'}");
&Verbose("CXXBIN = $ENV{'CXX'}");
&Verbose("CFLAGS = $ENV{'CFLAGS'}");
&Verbose("LDFLAGS = $ENV{'LDFLAGS'}");
&Verbose("PYTHONPATH = $ENV{'PYTHONPATH'}");

our $standard_make = '/usr/bin/make';
our $parallel_make = $standard_make;
our $parallel_make_flags = '';

my $cmd = "/usr/bin/hostinfo | grep 'processors\$'";
&Verbose($cmd);
my $cpus = `$cmd`; chomp $cpus;
$cpus =~ s/.*, (\d+) processors$/$1/;
if ( $cpus gt 1 )
{
    &Verbose("Using", $cpus+1, "jobs on $cpus parallel CPUs");
    ++$cpus;
    $parallel_make_flags = "-j$cpus";
}

if ($OPT{'noparallel'})
{
    $parallel_make_flags = '';
}
$parallel_make .= " $parallel_make_flags";

our %depend = (

    'git' =>
    {
        'url'           => 'http://www.kernel.org/pub/software/scm/git/git-1.7.3.4.tar.bz2',
        'parallel-make' => 'yes'
    },

    'freetype' =>
    {
        'url' => "$sourceforge/sourceforge/freetype/freetype-2.4.8.tar.gz",
    },

    'lame' =>
    {
        'url'           =>  "$sourceforge/sourceforge/lame/lame-3.99.5.tar.gz",
        'conf'          =>  [
            '--disable-frontend',
        ],
    },

    'libmad' =>
    {
        'url'           => "$sourceforge/sourceforge/mad/libmad-0.15.0b.tar.gz",
        'parallel-make' => 'yes'
    },

    'taglib' =>
    {
        'url'           => 'http://taglib.github.io/releases/taglib-1.11.1.tar.gz',
        'conf-cmd'      => "$PREFIX/bin/cmake",
        'conf'          => [
            "-DCMAKE_INSTALL_PREFIX=$PREFIX",
            "-DCMAKE_RELEASE_TYPE=Release",
            "-DBUILD_SHARED_LIBS=ON",
            "."
        ],
    },

    'libogg' =>
    {
        'url'           => 'http://downloads.xiph.org/releases/ogg/libogg-1.3.0.tar.gz',
        'pre-conf'      =>  'sed -i -e "s:-O4:-O3:g" configure',

    },

    'vorbis' =>
    {
        'url'           => 'http://downloads.xiph.org/releases/vorbis/libvorbis-1.3.2.tar.gz',
        'pre-conf'      =>  'sed -i -e "s:-O4:-O3:g" configure',
    },

    'flac' =>
    {
        'url'  => "http://downloads.xiph.org/releases/flac/flac-1.3.1.tar.xz",
    },

    'pkgconfig' =>
    {
        'url'           => "http://pkgconfig.freedesktop.org/releases/pkg-config-0.28.tar.gz",
        'conf-cmd'      =>  "CFLAGS=\"$ECFLAGS\" LDFLAGS=\"\" ./configure",
        'conf'          => [
            "--prefix=$PREFIX",
            "--disable-static",
            "--enable-shared",
            "--with-internal-glib",
        ],

    },

    'dvdcss' =>
    {
        'url'           =>  'http://download.videolan.org/pub/videolan/libdvdcss/1.2.11/libdvdcss-1.2.11.tar.bz2',
    },

    'boost' =>
    {
        'url'           =>  'https://sourceforge.net/projects/boost/files/boost/1.68.0/boost_1_68_0.tar.bz2',
        'conf-cmd'      =>  "./bootstrap.sh --prefix=$PREFIX",
        'make'          =>  ["install" ],
        'make-cmd'      =>  "./b2",
    },

    'ncurses' =>
    {
        'url'  => "https://ftp.gnu.org/pub/gnu/ncurses/ncurses-6.1.tar.gz",
        'conf'          => [
            "--prefix=$PREFIX",
            "--disable-static",
            "--with-shared",
        ],
    },

    'mysqlclient' =>
    {
        'url'           => 'http://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-5.7.22.tar.gz',
        # Need to do some cleanup, as mysql will not build if there's any old mysql headers installed there
        'pre-conf'      => "rm -rf $PREFIX/include/mysql $PREFIX/lib/libmysql*  $PREFIX/include/m_ctype.h $PREFIX/include/m_string.h $PREFIX/include/my_*.h $PREFIX/include/sql_*.h $PREFIX/include/mysql*.h $PREFIX/include/keycache.h $PREFIX/include/plugin.h $PREFIX/include/typelib.h $PREFIX/include/plugin_audit.h $PREFIX/include/sslopt-*.h $PREFIX/include/decimal.h $PREFIX/include/errmsg.h",
        'conf-cmd'      => "$PREFIX/bin/cmake",
        'conf'          => [
            "-DCMAKE_INSTALL_PREFIX=$PREFIX",
            "-DCURSES_INCLUDE_PATH=$SDKROOT/usr/include",
            "-DWITHOUT_SERVER=ON",
            "-DDOWNLOAD_BOOST=1",
            "-DWITH_BOOST=/Users/piotro/Devel/mythtv-master/.osx-packager/src/boost_src",
            "-DWITH_UNIT_TESTS=OFF",
        ],
        'make'          => [
            'all',
        ],
        'parallel-make' => 'yes',
        'post-make' => "SEGMENTS='SharedLibraries Development' ; for segment in \$SEGMENTS ; do $PREFIX/bin/cmake -DCMAKE_INSTALL_COMPONENT=\$segment -P cmake_install.cmake ; done; cp -v include/mysql.h $PREFIX/include/mysql/mysql.h",
    },

    'dbus' =>
    {
        'url' => 'http://dbus.freedesktop.org/releases/dbus/dbus-1.0.3.tar.gz',
        'post-make' => 'mv $PREFIX/lib/dbus-1.0/include/dbus/dbus-arch-deps.h '.
        ' $PREFIX/include/dbus-1.0/dbus ; '.
        'rm -fr $PREFIX/lib/dbus-1.0 ; '.
        'cd $PREFIX/bin ; '.
        'echo "#!/bin/sh
        if [ \"\$2\" = dbus-1 ]; then
        case \"\$1\" in
        \"--version\") echo 1.0.3  ;;
        \"--cflags\")  echo -I$PREFIX/include/dbus-1.0 ;;
        \"--libs\")    echo \"-L$PREFIX/lib -ldbus-1\" ;;
        esac
        fi
        exit 0"   > pkg-config ; '.
        'chmod 755 pkg-config'
    },

    'qtsqldriver'
    =>
    {
        'url' => "http://download.qt.io/official_releases/qt/5.15/5.15.2/single/qt-everywhere-src-5.15.2.tar.xz",
        'pre-conf'
        =>  "cd qtbase/src/plugins/sqldrivers/mysql; " .
            "sed -i '' 's/QMAKE_USE/# QMAKE_USE/g' mysql.pro; " .
            "cp mysql.pro mysql2.pro ; " .
            "echo \"target.path=$PREFIX/qtplugins-$QTVERSION\" >> mysql2.pro; " .
            "echo \"INSTALL += target\" >> mysql2.pro",
        'conf-cmd'
        =>  "cd qtbase/src/plugins/sqldrivers/mysql && $QTBIN/qmake \"QMAKE_CC=$CCBIN\" \"QMAKE_CXX=$CXXBIN\" \"QMAKE_CXXFLAGS=$ENV{'ECXXFLAGS'}\" \"QMAKE_CFLAGS=$ENV{'CFLAGS'}\" \"QMAKE_LFLAGS+='$ENV{'LDFLAGS'}'\" \"INCLUDEPATH+=$PREFIX/include/mysql\" \"LIBS+=-L$PREFIX/lib -lmysqlclient\" \"target.path=$PREFIX/qtplugins-$QTVERSION\" mysql2.pro",
        'arg-patches'   => "echo 5.5.1",
        'patches'       => {
            '5.5.1' => "sed -i '' 's/find xcrun/find xcodebuild/g' qtbase/mkspecs/features/mac/default_pre.prf",
        },
        'make-cmd' => 'cd qtbase/src/plugins/sqldrivers/mysql',
        'make' => [ ],
        'post-make' => 'cd qtbase/src/plugins/sqldrivers/mysql ; make install ; '.
            'make -f Makefile install ; '.
            '',
        'parallel-make' => 'yes'
    },

    'qtwebkit'
    =>
    {
        'url' => "https://github.com/qt/qtwebkit/archive/10cd6a106e1c461c774ca166a67b8c835c755ef7.zip",
        'conf-cmd'      => "cd qtwebkit-10cd6a106e1c461c774ca166a67b8c835c755ef7 ; $PREFIX/bin/cmake",
        'conf'          => [
            "-DCMAKE_INSTALL_PREFIX=$PREFIX",
            "-DCMAKE_VERBOSE_MAKEFILE=OFF",
            "-DCMAKE_BUILD_TYPE=Release",
            "-DPORT=Qt",
            "-DENABLE_TOOLS=OFF",
            "-DUSE_LIBHYPHEN=OFF",
            "-DCMAKE_CXX_FLAGS_RELEASE=\"-fPIC -fno-lto\"",
            "-DENABLE_PRINT_SUPPORT=OFF",
            "-DENABLE_API_TESTS=OFF",
            "-DENABLE_DEVICE_ORIENTATION=OFF",
            "-DENABLE_DRAG_SUPPORT=OFF",
            "-DENABLE_GAMEPAD_DEPRECATED=OFF",
            "-DENABLE_GEOLOCATION=OFF",
            "-DENABLE_INSPECTOR_UI=OFF",
            "-DENABLE_JIT=OFF",
            "-DENABLE_NETSCAPE_PLUGIN_API=OFF",
            "-DENABLE_PRINT_SUPPORT=OFF",
            "-DENABLE_QT_GESTURE_EVENTS=OFF",
            "-DENABLE_SPELLCHECK=OFF",
            "-DENABLE_TOUCH_EVENTS=OFF",
            "-DQt5_DIR=/Users/piotro/Devel/Qt5.14.2SDK/5.14.2/clang_64/lib/cmake/Qt5",
        ],
        'make'          => [
            'all',
        ],
        'parallel-make' => 'yes',
    },

    'exif' =>
    {
        'url'           => "$sourceforge/sourceforge/libexif/libexif-0.6.20.tar.bz2",
        'conf'          => [
            '--disable-docs'
        ]
    },

    'yasm' =>
    {
        'url'           => 'http://www.tortall.net/projects/yasm/releases/yasm-1.2.0.tar.gz',
    },

    'ccache' =>
    {
        'url'           => 'http://samba.org/ftp/ccache/ccache-3.1.4.tar.bz2',
        'parallel-make' => 'yes'
    },

    'libcddb' =>
    {
        'url'           => 'http://prdownloads.sourceforge.net/libcddb/libcddb-1.3.2.tar.bz2',
    },

    'libcdio' =>
    {
        'url'      => 'http://ftp.gnu.org/gnu/libcdio/libcdio-0.90.tar.gz',
    },

    'liberation-sans' =>
    {
        'url'      => 'https://fedorahosted.org/releases/l/i/liberation-fonts/liberation-fonts-ttf-1.07.1.tar.gz',
        'conf-cmd' => 'echo "all:" > Makefile',
        'make'     => [ ],
    },

    'firewiresdk' =>
    {
        'url'      => 'http://www.avenard.org/files/mac/AVCVideoServices.framework.tar.gz',
        'conf-cmd' => 'cd',
        'make-cmd' => "rm -rf $PREFIX/lib/AVCVideoServices.framework ; cp -R . $PREFIX/lib/AVCVideoServices.framework ; install_name_tool -id $PREFIX/lib/AVCVideoServices.framework/Versions/Current/AVCVideoServices $PREFIX/lib/AVCVideoServices.framework/Versions/Current/AVCVideoServices",
        'make'     => [ ],
    },

    'cmake'       =>
    {
        'url'           => 'https://cmake.org/files/v3.18/cmake-3.18.2.tar.gz',
        'parallel-make' => 'yes',
        'conf-cmd'      => "./configure",
        'conf'          =>  [
            "--prefix=$PREFIX",
        ],
    },

    'ninja' =>
    {
        'url'           =>  'https://github.com/martine/ninja/archive/v1.11.0.zip',
        'conf-cmd'      =>  "cd",
        'make-cmd'      =>  "cd ./ninja-1.11.0; $PYTHON ./configure.py --bootstrap",
        'make'          =>  [ ],
        'post-make'     =>  "cd ./ninja-1.11.0; cp -f ninja $PREFIX/bin/",
    },

    'libtool'     =>
    {
        'url'     => 'http://ftpmirror.gnu.org/libtool/libtool-2.4.6.tar.gz',
    },

    'autoconf'    =>
    {
        'url'     => 'http://ftp.gnu.org/gnu/autoconf/autoconf-2.68.tar.gz',
    },

    'automake'    =>
    {
        'url'     => 'http://ftp.gnu.org/gnu/automake/automake-1.11.tar.gz',
    },

    'libx264'     =>
    {
        'url'     => 'ftp://ftp.videolan.org/pub/videolan/x264/snapshots/x264-snapshot-20140331-2245-stable.tar.bz2',
        'conf-cmd' => "cd",
        'make-cmd' => "CFLAGS=\"$ECFLAGS\" LDFLAGS='' ./configure --prefix=$PREFIX --enable-shared; make $parallel_make_flags; " .
            "make install",
        'make'    => [ ],
        'arg-patches'   => "echo 20140331",
        'patches'       => {
            '20140331' => "patch -f -p0 <<EOF\n" . <<EOF
--- configure~	2014-04-01 07:45:07.000000000 +1100
+++ configure	2014-04-02 00:07:16.000000000 +1100
@@ -467,7 +467,6 @@
         ;;
     darwin*)
         SYS=\"MACOSX\"
-        CFLAGS=\"\\\$CFLAGS -falign-loops=16\"
         libm=\"-lm\"
         if [ \"\\\$pic\" = \"no\" ]; then
             cc_check \"\" -mdynamic-no-pic && CFLAGS=\"\\\$CFLAGS -mdynamic-no-pic\"
EOF
            . "\nEOF",
        },
    },

    'exiv2' =>
    {
        'url' => "https://github.com/Exiv2/exiv2/archive/exiv2-0.26.tar.gz",
        'conf-cmd'      => "$PREFIX/bin/cmake",
        'conf'          => [
            "-DCMAKE_INSTALL_PREFIX=$PREFIX",
            "-DCMAKE_RELEASE_TYPE=Release",
            "."
        ],
    },

    'openssl' =>
    { # we are NOT installing build opennssl as we are using system libs!!!. Only openssl headers are installed.
        'url' => "http://www.openssl.org/source/openssl-1.0.1c.tar.gz",
        'parallel-make' => 'yes',
        'conf-cmd'      => "./Configure",
        'conf'          =>  [
            "darwin64-x86_64-cc",
            "shared",
            "--prefix=$PREFIX",
        ],
        'make-cmd'      => "make all",
        'make'          => [ ],
        'post-make'     => "mkdir -p $PREFIX/include; cp -rf include/* $PREFIX/include/;",
    },

    'libsamplerate' =>
    {
        'url' => "http://www.mega-nerd.com/SRC/libsamplerate-0.1.9.tar.gz",
    },

    'libbluray' =>
    {
        'url' => "ftp://ftp.videolan.org/pub/videolan/libbluray/1.0.2/libbluray-1.0.2.tar.bz2",
        'conf'          =>  [
            "--without-fontconfig",
            "--disable-bdjava-jar",
        ],
    },

    'libxml2' =>
    {
        'url' => "ftp://xmlsoft.org/libxml2/libxml2-2.9.4.tar.gz",
        'conf'          =>  [
            "--without-python",
        ],
    },

    'lzo' =>
    {
        'url' => "http://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz",
    },

    'minizip' =>
    {
        'url' => "http://zlib.net/zlib-1.2.11.tar.xz",
        'pre-conf'      => "cd contrib/minizip; $PREFIX/bin/autoreconf --install",
        'conf-cmd'      => "cd contrib/minizip; configure",
        'conf'          => [
            "--prefix=$PREFIX",
            "--enable-shared",
        ],
        'make-cmd'      => "cd contrib/minizip; make all",
        'make'          => [ ],
        'post-make'     => "cd contrib/minizip; make install",
    },

    'soundtouch' =>
    {
        'url'           => "https://codeberg.org/soundtouch/soundtouch/archive/2.3.1.tar.gz",
        'conf-cmd'      => "$PREFIX/bin/cmake",
        'conf'          => [
            "-S soundtouch -B build -G Ninja",
            "-DCMAKE_INSTALL_PREFIX=$PREFIX",
            "-DCMAKE_RELEASE_TYPE=Release",
        ],
        'make-cmd'          => "mkdir -p build; $PREFIX/bin/cmake -S soundtouch -B build -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_RELEASE_TYPE=Release -DBUILD_SHARED_LIBS=ON; $PREFIX/bin/cmake --build build",
        'make'          => [ ],
        'post-make'     => "$PREFIX/bin/cmake --install build",
    },

    'fftw3' =>
    {
        'url' => "http://www.fftw.org/fftw-3.3.4.tar.gz",
        'conf'          =>  [
            "--enable-threads",
        ],
    },

    'fftw3f' =>
    {
        'url' => "http://www.fftw.org/fftw3f-3.3.4.tar.bz2",
        'conf'          =>  [
            "--enable-threads",
            "--enable-single",
        ],
    },

    'libzip' =>
    {
        'url' => "https://libzip.org/download/libzip-1.7.3.tar.xz",
        'conf-cmd'      => "$PREFIX/bin/cmake",
        'conf'          => [
            "-DCMAKE_INSTALL_PREFIX=$PREFIX",
            "-DCMAKE_RELEASE_TYPE=Release",
            "."
        ],
    },

    'python-setuptools' =>
    {
        'url'           => 'https://pypi.python.org/packages/source/s/setuptools/setuptools-20.3.1.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-mysql' =>
    {
        'url'           => 'https://pypi.python.org/packages/source/M/MySQL-python/MySQL-python-1.2.5.zip',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-lxml' =>
    {
        'url'           => 'https://files.pythonhosted.org/packages/ca/63/139b710671c1655aed3b20c1e6776118c62e9f9311152f4c6031e12a0554/lxml-4.2.4.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX --without-cython",
        'make'          => [ ],
    },

    'python-pycurl' =>
    {
        'url'           => 'https://files.pythonhosted.org/packages/e8/e4/0dbb8735407189f00b33d84122b9be52c790c7c3b25286826f4e1bdb7bde/pycurl-7.43.0.2.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py --with-ssl install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-pycurl-old' =>
    {
        'url'           => 'http://pycurl.sourceforge.net/download/pycurl-7.19.5.1.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py --with-ssl install --prefix=$PREFIX",
        'make'          => [ ],
        'arg-patches'   => "echo 7.19.5.1",
        'patches'       => {
            '7.19.5.1' => "patch -f -p0 <<EOF\n" . <<EOF
--- src/module.c~	2015-10-10 18:02:23.000000000 +1100
+++ src/module.c	2015-10-10 19:40:55.000000000 +1100
@@ -297,7 +297,7 @@
     /* Our compiled crypto locks should correspond to runtime ssl library. */
     if (vi->ssl_version == NULL) {
         runtime_ssl_lib = \"none/other\";
-    } else if (!strncmp(vi->ssl_version, \"OpenSSL/\", 8)) {
+    } else if (!strncmp(vi->ssl_version, \"OpenSSL/\", 8)  || !strncmp(vi->ssl_version, \"SecureTransport\", 15)) {
         runtime_ssl_lib = \"openssl\";
     } else if (!strncmp(vi->ssl_version, \"LibreSSL/\", 9)) {
         runtime_ssl_lib = \"openssl\";
EOF
            . "\nEOF",
        },
    },

    'python-urlgrabber' =>
    {
        'url'           => 'https://pypi.python.org/packages/source/u/urlgrabber/urlgrabber-3.9.1.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-simplejson' =>
    {
        'url'           => 'https://pypi.python.org/packages/source/s/simplejson/simplejson-3.3.3.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-oauth' =>
    {
        'url'           => 'https://files.pythonhosted.org/packages/e2/10/d7d6ae26ef7686109a10b3e88d345c4ec6686d07850f4ef7baefb7eb61e1/oauth-1.0.1.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-requests' =>
    {
        'url'           => 'https://github.com/kennethreitz/requests/archive/v2.18.4.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-certifi' =>
    {
        'url'           => 'https://pypi.python.org/packages/15/d4/2f888fc463d516ff7bf2379a4e9a552fef7f22a94147655d9b1097108248/certifi-2018.1.18.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-urllib3' =>
    {
        'url'           => 'https://pypi.python.org/packages/ee/11/7c59620aceedcc1ef65e156cc5ce5a24ef87be4107c2b74458464e437a5d/urllib3-1.22.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-idna' =>
    {
        'url'           => 'https://pypi.python.org/packages/f4/bd/0467d62790828c23c47fc1dfa1b1f052b24efdf5290f071c7a91d0d82fd3/idna-2.6.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-chardet' =>
    {
        'url'           => 'https://pypi.python.org/packages/fc/bb/a5768c230f9ddb03acc9ef3f0d4a3cf93462473795d18e9535498c8f929d/chardet-3.0.4.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-pyOpenSSL' =>
    {
        'url'           => 'https://pypi.python.org/packages/source/p/pyOpenSSL/pyOpenSSL-19.1.0.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-six' =>
    {
        'url'           => 'https://pypi.python.org/packages/source/s/six/six-1.10.0.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-pyasn1' =>
    {
        'url'           => 'https://pypi.python.org/packages/source/p/pyasn1/pyasn1-0.1.9.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-enum34' =>
    {
        'url'           => 'https://pypi.python.org/packages/source/e/enum34/enum34-1.1.2.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-ipaddress' =>
    {
        'url'           => 'https://pypi.python.org/packages/source/i/ipaddress/ipaddress-1.0.16.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-ordereddict' =>
    {
        'url'           => 'https://pypi.python.org/packages/source/o/ordereddict/ordereddict-1.1.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-pycparser' =>
    {
        'url'           => 'https://pypi.python.org/packages/source/p/pycparser/pycparser-2.14.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

    'python-cffi' =>
    {
        'url'           => 'https://pypi.python.org/packages/source/c/cffi/cffi-1.11.5.tar.gz',
        'pre-conf'      => "mkdir -p $PREFIX/lib/$PYTHON/site-packages",
        'conf-cmd'      => "cd",
        'make-cmd'      => "$PYTHON setup.py install --prefix=$PREFIX",
        'make'          => [ ],
    },

);

### Check for app present in target location
our $MFE = "$SCRIPTDIR/MythFrontend.app";
if ( -d $MFE && ! $OPT{'nobundle'} && ! $OPT{'distclean'} )
{
    &Complain(<<END);
$MFE already exists

Error: a MythFrontend application exists where we were planning
to build one. Please move this application away before running
this script.

END
    exit;
}

### Third party packages
my ( @build_depends, %seen_depends );
my @comps = ( 'mythtv', @components );

# Deal with user-supplied skip arguments
if ( $OPT{'mythtvskip'} )
{   @comps = grep(!m/mythtv/,      @comps)   }
if ( $OPT{'pluginskip'} )
{   @comps = grep(!m/mythplugins/, @comps)   }

if ( ! @comps )
{
    &Complain("Nothing to build! Too many ...skip arguments?");
    exit;
}

&Verbose("Including components:", @comps);

# If no Git in path, and we are checking something out, build Git:
if ( ( ! $git || $git =~ m/no git in / ) && ! $OPT{'nohead'} )
{
    $git = "$PREFIX/bin/git";
    @build_depends = ( 'git' );
}

foreach my $comp (@comps)
{
    foreach my $dep (@{ $depend_order{$comp} })
    {
        unless (exists $seen_depends{$dep})
        {
            push(@build_depends, $dep);
            $seen_depends{$dep} = 1;
        }
    }
}

#If building backend, include libx264
if ( $backend )
{
    &Verbose("Adding x264 encoding capabilities");
    push(@build_depends,'libx264');
    $seen_depends{'libx264'} = 1;
}

foreach my $sw ( @build_depends )
{
    # Get info about this package
    my $pkg = $depend{$sw};
    my $url = $pkg->{'url'};
    my $filename = $url;
    $filename =~ s|^.+/([^/]+)$|$1|;
    my $dirname = $filename;
    $filename = $ARCHIVEDIR . '/' . $filename;
    $dirname =~ s|\.tar\.gz$||;
    $dirname =~ s|\.tar\.xz$||;
    $dirname =~ s|\.tar\.bz2$||;
    $dirname =~ s|\.zip$||;

    chdir($SRCDIR);

    # Download and decompress
    unless ( -e $filename )
    {
        &Verbose("Downloading $sw");
        unless (&Syscall([ '/usr/bin/curl', '-f', '-L', $url, '>', $filename ],
                         'munge' => 1))
        {
            &Syscall([ '/bin/rm', $filename ]) if (-e $filename);
            die;
        }
    }
    else
    {   &Verbose("Using previously downloaded $sw")   }

    if ( $pkg->{'skip'} )
    {   next   }

    if ( -d $dirname )
    {
        if ( $OPT{'thirdclean'} )
        {
            &Verbose("Removing previous build of $sw");
            &Syscall([ '/bin/rm', '-f', '-r', $dirname ]) or die;
        }

        if ( $OPT{'thirdskip'} )
        {
            &Verbose("Using previous build of $sw");
            next;
        }

        &Verbose("Using previously unpacked $sw");
    }
    else
    {
        &Verbose("Unpacking $sw");
        if ( substr($filename,-3) eq ".gz" )
        {   &Syscall([ '/usr/bin/tar', '-xzf', $filename ]) or die   }
        elsif ( substr($filename,-4) eq ".bz2" )
        {   &Syscall([ '/usr/bin/tar', '-xjf', $filename ]) or die   }
        elsif ( substr($filename,-4) eq ".zip" )
        {   &Syscall([ '/usr/bin/unzip', $filename ])       or die   }
        elsif ( substr($filename,-3) eq ".xz" )
        {   &Syscall([ '/usr/bin/tar', '-xf', $filename ]) or die   }
        else
        {
            &Complain("Cannot unpack file $filename");
            exit;
        }
    }

    # Configure
    chdir($dirname);
    unless (-e '.osx-config')
    {
        &Verbose("Configuring $sw");
        if ( $pkg->{'pre-conf'} )
        {   &Syscall([ $pkg->{'pre-conf'} ], 'munge' => 1) or die   }

        my (@configure, $munge);

        my $arg = $pkg->{'arg-patches'};
        my $patches = $pkg->{'patches'};
        if ( $arg && $patches )
        {
            $arg        = `$arg`; chomp $arg;
            my $patch   = $patches->{$arg};
            if ( $patch )
            {
                &Syscall($patch);
            }
        }
        if ( $pkg->{'conf-cmd'} )
        {
            my $tmp = $pkg->{'conf-cmd'};
            push(@configure, $tmp);
            $munge = 1;
        }
        else
        {
            push(@configure, "./configure",
                       "--prefix=$PREFIX",
                       "--disable-static",
                       "--enable-shared");
        }
        if ( $pkg->{'conf'} )
        {
            push(@configure, @{ $pkg->{'conf'} });
        }
        &Syscall(\@configure, 'interpolate' => 1, 'munge' => $munge) or die;
        if ( $pkg->{'post-conf'} )
        {
            &Syscall([ $pkg->{'post-conf'} ], 'munge' => 1) or die;
        }
        &Syscall([ '/usr/bin/touch', '.osx-config' ]) or die;
    }
    else
    {   &Verbose("Using previously configured $sw")   }

    # Build and install
    unless (-e '.osx-built')
    {
        &Verbose("Making $sw");
        my (@make);

        if ( $pkg->{'make-cmd' } )
        {
            push(@make, $pkg->{'make-cmd' });
        }
        else
        {
            push(@make, $standard_make);
            if ( $pkg->{'parallel-make'} && $parallel_make_flags )
            {   push(@make, $parallel_make_flags)   }
        }
        if ( $pkg->{'make'} )
        {   push(@make, @{ $pkg->{'make'} })   }
        else
        {   push(@make, 'all', 'install')   }

        &Syscall(\@make) or die;
        if ( $pkg->{'post-make'} )
        {
            &Syscall([ $pkg->{'post-make'} ], 'munge' => 1) or die;
        }
        &Syscall([ '/usr/bin/touch', '.osx-built' ]) or die;
    }
    else
    {
        &Verbose("Using previously built $sw");
    }
}

if ( $OPT{'bootstrap'} )
{
    exit;
}

if ( ! $OPT{'nodistclean'} )
{
    if ( $OPT{'mythtvskip'} )
    {
        &Complain("Cannot skip building mythtv src if also cleaning, use -nodistclean");
        exit;
    }
    &Distclean(""); # Clean myth system installed libraries
}

foreach my $arch (@ARCHS)
{
    ### build MythTV
    &Verbose("Compiling for $arch architecture");

    # Clean any previously installed libraries
    if ( ! $OPT{'nodistclean'} )
    {
        &Verbose("Cleaning previous installs of MythTV for arch: $arch");
        &Distclean($arch);
    }

    # show summary of build parameters.
    &Verbose("CFLAGS = $ENV{'CFLAGS'}");
    &Verbose("CXXFLAGS = $ENV{'CXXFLAGS'}");
    &Verbose("LDFLAGS = $ENV{'LDFLAGS'}");

    # Build MythTV and any plugins
    foreach my $comp (@comps)
    {
        my $compdir = "$GITDIR/$comp/" ;

        chdir $compdir || die "No source directory $compdir";

        if ( ! -e "$comp.pro" and ! -e 'Makefile' and ! -e 'configure' )
        {
            &Complain("Nothing to configure/make in $compdir for $arch");
            next;
        }

        if ( ($OPT{'distclean'} || ! $OPT{'noclean'}) && -e 'Makefile' )
        {
            &Verbose("Cleaning $comp for $arch");
            &Syscall([ $standard_make, 'distclean' ]);
        }
        next if $OPT{'distclean'};

        # Apply any nasty mac-specific patches
        if ( $patches{$comp} )
        {
            &Syscall([ "echo '$patches{$comp}' | patch -p0 --forward" ]);
        }

        # configure and make
        if ( $makecleanopt{$comp} && -e 'Makefile' && ! $OPT{'noclean'} )
        {
            my @makecleancom = $standard_make;
            push(@makecleancom, @{ $makecleanopt{$comp} }) if $makecleanopt{$comp};
            &Syscall([ @makecleancom ]) or die;
        }

        if ( -e 'configure' && ! $OPT{'noclean'} )
        {
            &Verbose("Configuring $comp for $arch");
            my @config = './configure';
            push(@config, @{ $conf{$comp} }) if $conf{$comp};
            push @config, "--prefix=$PREFIX";
            push @config, "--cc=$CCBIN";
            push @config, "--cxx=$CXXBIN";
            push @config, "--qmake=$QTBIN/qmake";
            push @config, "--extra-libs=-F$QTLIB";

            if ( $comp eq "mythtv" )
            {
                # Test if configure supports --firewire-sdk option
                my $result = `./configure --help | grep -q firewire-sdk`;
                if ( $? == 0 )
                {
                    push @config, "--firewire-sdk=$PREFIX/lib";
                }
                if ( exists $seen_depends{"libx264"} )
                {
                    push @config, "--enable-libx264";
                }
                if ( $OPT{'no-optimization'} )
                {
                    push @config, "--disable-optimizations";
                }
                if ( $OPT{'disable-checks'} )
                {
                    push @config, '--extra-cxxflags=-DIGNORE_SCHEMA_VER_MISMATCH=1 -DIGNORE_PROTO_VER_MISMATCH=1';
                }
                push @config, "--disable-ccache";
                push @config, "--disable-libxml2";
                push @config, "--pkg-config=$WORKDIR/build/bin/pkg-config";
            }

            if ( $OPT{'profile'} )
            {
                push @config, '--compile-type=profile'
            }
            if ( $OPT{'debug'} )
            {
                push @config, '--compile-type=debug'
            }
            &Syscall([ @config ]) or die;
        }
        if ( (! -e 'configure') && -e "$comp.pro" && ! $OPT{'noclean'} )
        {
            &Verbose("Running qmake for $comp for $arch");
            my @qmake_opts = (
                "\"QMAKE_CC=$CCBIN\" \"QMAKE_CXX=$CXXBIN\" \"QMAKE_CXXFLAGS=$ENV{'CXXFLAGS'}\" \"QMAKE_CFLAGS=$ENV{'CFLAGS'}\" \"QMAKE_LFLAGS+=$ENV{'LDFLAGS'}\"",
                "INCLUDEPATH+=\"$PREFIX/include\"",
                "LIBS+=\"-F$QTLIB -L\"$PREFIX/lib\"",
                );
            &Syscall([ "$QTBIN/qmake",
                       'PREFIX=../Resources',
                       @qmake_opts,
                       "$comp.pro" ]) or die;
        }

        &Verbose("Making $comp");
        &Syscall([ $parallel_make ]) or die;

        &Verbose("Installing $comp");
        &Syscall([ $standard_make, 'install' ]) or die;

        if ( $cleanLibs && $comp eq 'mythtv' )
        {
            # If we cleaned the libs, make install will have recopied them,
            # which means any dynamic libraries that the static libraries depend on
            # are newer than the table of contents. Hence we need to regenerate it:
            my @mythlibs = glob "$PREFIX/lib/libmyth*.a";
            if ( scalar @mythlibs )
            {
                &Verbose("Running ranlib on reinstalled static libraries");
                foreach my $lib (@mythlibs)
                {   &Syscall("ranlib $lib") or die }
            }
        }
    }
}

if ( $OPT{'distclean'} )
{
    &Complain("Distclean done ..");
    exit;
}
&Complain("Compilation done ..");

# stop here if no bundle is to be created
if ( $OPT{'nobundle'} )
{
    exit;
}

### Program which creates bundles:
our @bundler = "$GITDIR/packaging/OSX/build/osx-bundler.pl";
if ( $OPT{'verbose'} )
{   push @bundler, '-verbose'   }

# Determine version number
$GITVERSION = `cd $GITDIR && $git describe` ; chomp $GITVERSION;
if ( $? != 0)
{
    $GITVERSION = `find $PREFIX/lib -name 'libmyth-[0-9].[0-9][0-9].[0-9].dylib' | tail -1`;
    chomp $GITVERSION;
    $GITVERSION =~ s/^.*\-(.*)\.dylib$/$1/s;
}
push @bundler, '-longversion', $GITVERSION;
push @bundler, '-shortversion', $GITVERSION;

### Create each package.
### Note that this is a bit of a waste of disk space,
### because there are now multiple copies of each library.

if ( $jobtools )
{   push @targets, @targetsJT   }

if ( $backend )
{   push @targets, @targetsBE   }

my @libs = ( "$PREFIX/lib/", "$PREFIX/lib/mysql", "$QTLIB" );
foreach my $target ( @targets )
{
    my $finalTarget = "$SCRIPTDIR/$target.app";
    my $builtTarget = lc $target;

    # Get a fresh copy of the binary
    &Verbose("Building self-contained $target");
    &Syscall([ 'rm', '-fr', $finalTarget ]) or die;
    &Syscall([ 'cp',  "$PREFIX/bin/$builtTarget",
                      "$SCRIPTDIR/$target" ]) or die;

    # Convert it to a bundled .app
    &Syscall([ @bundler, "$SCRIPTDIR/$target", @libs ]) or die;

    # Remove copy of binary
    unlink "$SCRIPTDIR/$target" or die;

    # Themes are required by all GUI apps. The filters and plugins are not
    # used by mythtv-setup or mythwelcome, but for simplicity, do them all.
    if ( $target eq "MythFrontend" or
         $target eq "MythWelcome" or $target =~ m/^MythTV-/ )
    {
        my $res  = "$finalTarget/Contents/Resources";
        my $libs = "$res/lib";
        my $plug = "$libs/mythtv/plugins";

        # Install themes, filters, etc.
        &Verbose("Installing resources into $target");
        mkdir $res; mkdir $libs;
        &RecursiveCopy("$PREFIX/lib/mythtv", $libs);
        mkdir "$res/share";
        &RecursiveCopy("$PREFIX/share/mythtv", "$res/share");

        # Correct the library paths for the filters and plugins
        foreach my $lib ( glob "$libs/mythtv/*/*" )
        {   &Syscall([ @bundler, $lib, @libs ]) or die   }

        if ( -e $plug )
        {
            # Allow Finder's 'Get Info' to manage plugin list:
            &Syscall([ 'mv', $plug, "$finalTarget/Contents/$BundlePlugins" ]) or die;
            &Syscall([ 'ln', '-s', "../../../$BundlePlugins", $plug ]) or die;
        }

        # The icon
        &Syscall([ 'cp',
                   "$GITDIR/mythtv/programs/mythfrontend/mythfrontend.icns",
                   "$res/application.icns" ]) or die;
        &Syscall([ 'xcrun', '-sdk', "$SDKNAME", 'SetFile', '-a', 'C', $finalTarget ])
            or die;

        # Create PlugIns directory
        mkdir("$finalTarget/Contents/PlugIns");

        # Tell Qt to use the PlugIns for the Qt plugins
        open FH, ">$res/qt.conf";
        print FH "[Paths]\nPlugins = $BundlePlugins\n";
        close FH;

        if ( $OPT{'qtsrc'} && -d "$PREFIX/lib/qt_menu.nib" )
        {
            if ( -d "$finalTarget/Contents/Frameworks/QtGui.framework/Resources" )
            {
                &Syscall([ 'cp', '-R', "$PREFIX/lib/qt_menu.nib", "$finalTarget/Contents/Frameworks/QtGui.framework/Resources" ]);
            }
            else
            {
                &Syscall([ 'cp', '-R', "$PREFIX/lib/qt_menu.nib", "$finalTarget/Contents/Resources" ]);
            }
        }

        # Copy the required Qt plugins
        foreach my $plugin ( "imageformats", "platforms")
        {
            &Syscall([ 'mkdir', "$finalTarget/Contents/$BundlePlugins/$plugin" ]) or die;
            # Have to create links in application folder due to QTBUG-24541
            &Syscall([ 'ln', '-s', "../$BundlePlugins/$plugin", "$finalTarget/Contents/MacOS/$plugin" ]) or die;
        }

        foreach my $plugin ( 'imageformats/libqgif.dylib', 'imageformats/libqjpeg.dylib', 'platforms/libqcocoa.dylib')
        {
            my $pluginSrc = "$QTPLUGINS/$plugin";
            if ( -e $pluginSrc )
            {
                my $pluginCp = "$finalTarget/Contents/$BundlePlugins/$plugin";
                &Syscall([ 'cp', $pluginSrc, $pluginCp ]) or die;
                &Syscall([ @bundler, $pluginCp, @libs ])  or die;
            }
            else
            {
                &Complain("missing plugin $pluginSrc");
            }
        }

        # A font the Terra theme uses:
        my $url = $depend{'liberation-sans'}->{'url'};
        my $dirname = $url;
        $dirname =~ s|^.+/([^/]+)$|$1|;
        $dirname =~ s|\.tar\.gz$||;
        $dirname =~ s|\.tar\.bz2$||;

        my $fonts = "$res/share/mythtv/fonts";
        mkdir $fonts;
        &RecursiveCopy("$SRCDIR/$dirname/LiberationSans-Regular.ttf", $fonts);
        &EditPList("$finalTarget/Contents/Info.plist",
                   'ATSApplicationFontsPath', 'share/mythtv/fonts');
    }

    if ( $target eq "MythFrontend" )
    {
        my $extralib;
        my @list = ( 'mythavtest', 'ignyte', 'mythpreviewgen', 'mtd', 'mythscreenwizard' );
        if ( $OPT{'enable-mythlogserver'} )
        {
            push @list, "mythlogserver";
        }

        foreach my $extra (@list)
        {
            if ( -e "$PREFIX/bin/$extra" )
            {
                &Verbose("Installing $extra into $target");
                &Syscall([ 'cp', "$PREFIX/bin/$extra",
                           "$finalTarget/Contents/MacOS" ]) or die;

                &Verbose('Updating lib paths of',
                         "$finalTarget/Contents/MacOS/$extra");
                &Syscall([ @bundler, "$finalTarget/Contents/MacOS/$extra", @libs ])
                    or die;
            }
        }
        &AddFakeBinDir($finalTarget);

        # Allow playback of region encoded DVDs
        $extralib = "libdvdcss.2.dylib";
        &Syscall([ 'cp', "$PREFIX/lib/$extralib",
                         "$finalTarget/Contents/Frameworks" ]) or die;
        &Syscall([ @bundler, "$finalTarget/Contents/Frameworks/$extralib", @libs ])
            or die;
    }

    if ( $target eq "MythWelcome" )
    {
        &Verbose("Installing mythfrontend into $target");
        &Syscall([ 'cp', "$PREFIX/bin/mythfrontend",
                         "$finalTarget/Contents/MacOS" ]) or die;
        &Syscall([ @bundler, "$finalTarget/Contents/MacOS/mythfrontend", @libs ])
            or die;
        &AddFakeBinDir($finalTarget);

        # For some unknown reason, mythfrontend looks here for support files:
        &Syscall([ 'ln', '-s', "../Resources/share",   # themes
                               "../Resources/lib",     # filters/plugins
                   "$finalTarget/Contents/MacOS" ]) or die;
    }

    # Copy the required Qt plugins
    foreach my $plugin ( "sqldrivers" )
    {
        &Syscall([ 'mkdir', "-p", "$finalTarget/Contents/$BundlePlugins/$plugin" ]) or die;
        # Have to create links in application folder due to QTBUG-24541
        &Syscall([ 'ln', '-s', "../$BundlePlugins/$plugin", "$finalTarget/Contents/MacOS/$plugin" ]) or die;
    }

    # copy the MySQL sqldriver
    &Syscall([ 'cp', "$PREFIX/qtplugins-$QTVERSION/libqsqlmysql.dylib", "$finalTarget/Contents/$BundlePlugins/sqldrivers/" ])
    or die;
    &Syscall([ @bundler, "$finalTarget/Contents/$BundlePlugins/sqldrivers/libqsqlmysql.dylib", @libs ])
    or die;

    if ( $target eq "MythFrontend" or $target eq "MythBackend" )
    {
        # copy python plugins
        &Syscall([ 'mkdir', "-p", "$finalTarget/Contents/Resources/lib/$PYTHON" ]) or die;
        &RecursiveCopy("$PREFIX/lib/$PYTHON/site-packages", "$finalTarget/Contents/Resources/lib/$PYTHON");
    }

}

if ( $backend && grep(m/MythBackend/, @targets) )
{
    my $BE = "$SCRIPTDIR/MythBackend.app";

    # Copy XML files that UPnP requires:
    my $share = "$BE/Contents/Resources/share/mythtv";
    &Syscall([ 'mkdir', '-p', $share ]) or die;
    &Syscall([ 'cp', glob("$PREFIX/share/mythtv/*.xml"), $share ]) or die;

    # Same for default web server page:
    &Syscall([ 'cp', '-pR', "$PREFIX/share/mythtv/html", $share ]) or die;

    # The backend gets all the useful binaries it might call:
    my @list = ( 'mythjobqueue', 'mythcommflag',
    'mythpreviewgen', 'mythtranscode', 'mythfilldatabase' );
    if ( $OPT{'enable-mythlogserver'} )
    {
        push @list, "mythlogserver";
    }

    foreach my $binary (@list)
    {
        my $SRC  = "$PREFIX/bin/$binary";
        if ( -e $SRC )
        {
            &Verbose("Installing $SRC into $BE");
            &Syscall([ '/bin/cp', $SRC, "$BE/Contents/MacOS" ]) or die;

            &Verbose("Updating lib paths of $BE/Contents/MacOS/$binary");
            &Syscall([ @bundler, "$BE/Contents/MacOS/$binary", @libs ]) or die;
        }
    }
    &AddFakeBinDir($BE);
}

if ( $backend && grep(m/MythTV-Setup/, @targets) )
{
    my $SET = "$SCRIPTDIR/MythTV-Setup.app";
    my $SRC  = "$PREFIX/bin/mythfilldatabase";
    if ( -e $SRC )
    {
        &Verbose("Installing $SRC into $SET");
        &Syscall([ '/bin/cp', $SRC, "$SET/Contents/MacOS" ]) or die;

        &Verbose("Updating lib paths of $SET/Contents/MacOS/mythfilldatabase");
        &Syscall([ @bundler, "$SET/Contents/MacOS/mythfilldatabase", @libs ]) or die;
    }
    &AddFakeBinDir($SET);
}

if ( $jobtools )
{
    # JobQueue also gets some binaries it might call:
    my $JQ   = "$SCRIPTDIR/MythJobQueue.app";
    my $DEST = "$JQ/Contents/MacOS";
    my $SRC  = "$PREFIX/bin/mythcommflag";

    &Syscall([ '/bin/cp', $SRC, $DEST ]) or die;
    &AddFakeBinDir($JQ);
    &Verbose("Updating lib paths of $DEST/mythcommflag");
    &Syscall([ @bundler, "$DEST/mythcommflag", @libs ]) or die;

    $SRC  = "$PREFIX/bin/mythtranscode.app/Contents/MacOS/mythtranscode";
    if ( -e $SRC )
    {
        &Verbose("Installing $SRC into $JQ");
        &Syscall([ '/bin/cp', $SRC, $DEST ]) or die;
        &Verbose("Updating lib paths of $DEST/mythtranscode");
        &Syscall([ @bundler, "$DEST/mythtranscode", @libs ]) or die;
    }
}

# Clean tmp files. Most of these are leftovers from configure:
#
&Verbose('Cleaning build tmp directory');
&Syscall([ 'rm', '-fr', $WORKDIR . '/tmp' ]) or die;
&Syscall([ 'mkdir',     $WORKDIR . '/tmp' ]) or die;

if ($OPT{usehdimage} && !$OPT{leavehdimage} )
{
    Verbose("Dismounting case-sensitive build device");
    UnmountHDImage();
}

&Verbose("Build complete. Self-contained package is at:\n\n    $MFE\n");

### end script
exit 0;


######################################
## RecursiveCopy copies a directory tree, stripping out .git
## directories and properly managing static libraries.
######################################

sub RecursiveCopy($$)
{
    my ($src, $dst) = @_;

    # First copy absolutely everything
    &Syscall([ '/bin/cp', '-pR', "$src", "$dst"]);

    # Then strip out any .git directories
    my @files = map { chomp $_; $_ } `find $dst -name .git`;
    if ( scalar @files )
    {
        &Syscall([ '/bin/rm', '-f', '-r', @files ]);
    }

    # And make sure any static libraries are properly relocated.
    my @libs = map { chomp $_; $_ } `find $dst -name "lib*.a"`;
    if ( scalar @libs )
    {
        &Syscall([ 'ranlib', '-s', @libs ]);
    }
}

######################################
## CleanMakefiles removes every generated Makefile
## from our MythTV build that contains PREFIX.
## Necessary when we change the
## PREFIX variable.
######################################

sub CleanMakefiles
{
    &Verbose("Cleaning MythTV makefiles containing PREFIX");
    &Syscall([ 'find', '.', '-name', 'Makefile', '-exec',
               'egrep', '-q', 'qmake.*PREFIX', '{}', ';', '-delete' ]) or die;
} # end CleanMakefiles


######################################
## Syscall wrappers the Perl "system"
## routine with verbosity and error
## checking.
######################################

sub Syscall($%)
{
    my ($arglist, %opts) = @_;

    unless (ref $arglist)
    {
        $arglist = [ $arglist ];
    }
    if ( $opts{'interpolate'} )
    {
        my @args;
        foreach my $arg (@$arglist)
        {
            $arg =~ s/\$PREFIX/$PREFIX/ge;
            $arg =~ s/\$SDKROOT/$SDKROOT/ge;
            $arg =~ s/\$CFLAGS/$ENV{'CFLAGS'};/ge;
            $arg =~ s/\$LDFLAGS/$ENV{'LDFLAGS'};/ge;
            $arg =~ s/\$parallel_make_flags/$parallel_make_flags/ge;
            push(@args, $arg);
        }
        $arglist = \@args;
    }
    if ( $opts{'munge'} )
    {
        $arglist = [ join(' ', @$arglist) ];
    }
    # clean out any null arguments
    $arglist = [ map $_, @$arglist ];
    &Verbose(@$arglist);
    my $ret = system(@$arglist);
    if ( $ret )
    {
        &Complain('Failed system call: "', @$arglist,
                  '" with error code', $ret >> 8);
    }
    return ($ret == 0);
} # end Syscall


######################################
## Verbose prints messages in verbose
## mode.
######################################

sub Verbose
{
    print STDERR '[osx-pkg] ' . join(' ', @_) . "\n"
        if $OPT{'verbose'};
} # end Verbose


######################################
## Complain prints messages in any
## verbosity mode.
######################################

sub Complain
{
    print STDERR '[osx-pkg] ' . join(' ', @_) . "\n";
} # end Complain


######################################
## Manage usehdimage disk image
######################################

sub MountHDImage
{
    if ( ! HDImageDevice() )
    {
        if ( -e "$SCRIPTDIR/.osx-packager.dmg" )
        {
            Verbose("Mounting existing UFS disk image for the build");
        }
        else
        {
            Verbose("Creating a case-sensitive (UFS) disk image for the build");
            Syscall(['hdiutil', 'create', '-size', '2048m',
                     "$SCRIPTDIR/.osx-packager.dmg", '-volname',
                     'MythTvPackagerHDImage', '-fs', 'UFS', '-quiet']) || die;
        }

        &Syscall(['hdiutil', 'mount',
                  "$SCRIPTDIR/.osx-packager.dmg",
                  '-mountpoint', $WORKDIR, '-quiet']) || die;
    }

    # configure defaults to /tmp and OSX barfs when mv crosses
    # filesystems so tell configure to put temp files on the image

    $ENV{TMPDIR} = $WORKDIR . "/tmp";
    mkdir $ENV{TMPDIR};
}

sub UnmountHDImage
{
    my $device = HDImageDevice();
    if ( $device )
    {
        &Syscall(['hdiutil', 'detach', $device, '-force']);
    }
}

sub HDImageDevice
{
    my @dev = split ' ', `/sbin/mount | grep $WORKDIR`;
    $dev[0];
}

sub CaseSensitiveFilesystem
{
    my $funky = $SCRIPTDIR . "/.osx-packager.FunkyStuff";
    my $unfunky = substr($funky, 0, -10) . "FUNKySTuFF";

    unlink $funky if -e $funky;
    `touch $funky`;
    my $sensitivity = ! -e $unfunky;
    unlink $funky;

    return $sensitivity;
}


#######################################################
## Parts of MythTV try to call helper apps like this:
## gContext->GetInstallPrefix() + "/bin/mythtranscode";
## which means we need a bin directory.
#######################################################

sub AddFakeBinDir($)
{
    my ($target) = @_;

    &Syscall("mkdir -p $target/Contents/Resources");
    &Syscall(['ln', '-sf', '../MacOS', "$target/Contents/Resources/bin"]);
}

###################################################################
## Update or add <dict> properties in a (non-binary) .plist file ##
###################################################################

sub EditPList($$$)
{
    my ($file, $key, $value) = @_;

    &Verbose("Looking for property $key in file $file");

    open(IN,  $file)         or die;
    open(OUT, ">$file.edit") or die;
    while ( <IN> )
    {
        if ( m,\s<key>$key</key>, )
        {
            <IN>;
            &Verbose("Value was $_");  # Does this work?
            print OUT "<key>$key</key>\n<string>$value</string>\n";
            next;
        }
        elsif ( m,^</dict>$, )  # Not there. Add at end
        {
            print OUT "<key>$key</key>\n<string>$value</string>\n";
            print OUT "</dict>\n</plist>\n";
            last;
        }

        print OUT;
    }
    close IN; close OUT;
    rename("$file.edit", $file);
}

sub Distclean
{
    my $arch = $_[0];
    if ( $arch ne "" )
    {
        $arch .= "/";
    }
    &Syscall("/bin/rm -fr $PREFIX/${arch}include/mythtv");
    &Syscall("/bin/rm -f  $PREFIX/${arch}bin/myth*"     );
    &Syscall("/bin/rm -fr $PREFIX/${arch}lib/libmyth*"  );
    &Syscall("/bin/rm -fr $PREFIX/${arch}lib/mythtv"    );
    &Syscall("/bin/rm -fr $PREFIX/${arch}share/mythtv"  );
    &Syscall("/bin/rm -fr $PREFIX/${arch}share/mythtv"  );
    &Syscall([ 'find', "$GITDIR/", '-name', '*.o',     '-delete' ]);
    &Syscall([ 'find', "$GITDIR/", '-name', '*.a',     '-delete' ]);
    &Syscall([ 'find', "$GITDIR/", '-name', '*.dylib', '-delete' ]);
    &Syscall([ 'find', "$GITDIR/", '-name', '*.orig',  '-delete' ]);
    &Syscall([ 'find', "$GITDIR/", '-name', '*.rej',   '-delete' ]);
}

### end file
1;
