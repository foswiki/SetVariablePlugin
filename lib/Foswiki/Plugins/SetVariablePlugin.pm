# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006-2018 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#

package Foswiki::Plugins::SetVariablePlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Request ();

BEGIN {
  # Backwards compatibility for Foswiki 1.1.x
  unless (Foswiki::Request->can('multi_param')) {
    no warnings 'redefine';
    *Foswiki::Request::multi_param = \&Foswiki::Request::param;
    use warnings 'redefine';
  }
}

our $VERSION = "3.00";
our $RELEASE = "11 Jun 2018";

our $SHORTDESCRIPTION = 'Flexible handling of topic variables';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

###############################################################################
sub initPlugin {
  my ($topic, $web, $user, $installWeb) = @_;

  Foswiki::Func::registerTagHandler('SETVAR', sub {
    getCore()->handleSetVar(@_) if Foswiki::Func::getContext()->{save};
    return '<!-- -->' ;
  });

  Foswiki::Func::registerTagHandler('GETVAR', sub { 
    return getCore()->handleGetVar(@_); 
  });

  Foswiki::Func::registerTagHandler('DELVAR', sub { 
    getCore()->handleUnsetVar(@_) if Foswiki::Func::getContext()->{save};
    return '<!-- -->' ;
  });

  Foswiki::Func::registerTagHandler('UNSETVAR', sub { 
    getCore()->handleUnsetVar(@_) if Foswiki::Func::getContext()->{save};
    return '<!-- -->' ;
  });

  $core = undef;

  return 1;
}

###############################################################################
sub getCore {
  return $core if $core;

  require Foswiki::Plugins::SetVariablePlugin::Core;
  $core = new Foswiki::Plugins::SetVariablePlugin::Core;

  return $core;
}

###############################################################################
sub beforeSaveHandler { 
  return getCore()->handleBeforeSave(@_); 
}


1;
