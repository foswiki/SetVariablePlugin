# Copyright (C) 2007-2025 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at 
# http://www.gnu.org/copyleft/gpl.html
#
package Foswiki::Plugins::SetVariablePlugin::Core;

use strict;
use warnings;

use Foswiki::Func ();

use constant TRACE => 0; # toggle me
use constant ACTION_UNSET => 0;
use constant ACTION_SET => 1;

# constructor
sub new {
  my $class = shift;

  return bless({}, $class);
}

sub finish {
  my $this = shift;

  undef $this->{_template};
}

sub addRule {
  my $this = shift;
  my $action = shift;

  my $record = {
    action => $action,
    @_
  };

  push @{$this->{rules}}, $record;

  return $record;
}

sub applyRules {
  my ($this, $web, $topic, $meta, $text) = @_;

  return unless $this->{rules};

  $text ||= '';

  if (TRACE) {
    require Data::Dumper;
    _writeDebug(Data::Dumper->Dump([$this->{rules}]));
  }

  my @fields = $meta->find('FIELD');

  # itterate over all rules in the given order 
  foreach my $record (sort {$b->{prio} <=> $a->{prio}} @{$this->{rules}}) {

    # check conditions
    my $found;
    if ($record->{field}) {
      next unless defined $record->{regex}; # illegal rule
      foreach my $field (@fields) {
        my $name = $field->{name} // '';
        my $value = $field->{value} // '';
        if ($name eq $record->{field} && $value =~ /^($record->{regex})$/) {
          $found = $field;
          last;
        }
      }
      next unless defined $found;
    } else {
      if ($record->{regex}) { # check against topic text
        next unless $text =~ /$record->{regex}/;
      }
    }

    # get settings 
    my @vars = split(/\s*,\s*/, $record->{var});
    my $type = $record->{type} || 'Local';
    $found //= {};
    my $value = _expandVariables($record->{format} // $record->{value}, %$found);
    $value = Foswiki::Func::expandCommonVariables($value, $topic, $web) if defined $value && $value =~ /%/;

    if ($record->{action} eq ACTION_SET && defined($value) && $value ne 'undef') {
      foreach my $var (@vars) {
        _writeDebug("... setting preference $var to $value, type=$type, prio=$record->{prio}");
        $meta->putKeyed('PREFERENCE', {name=>$var, title => $var, value => $value, type => $type});
      }
    } else { # unset
      foreach my $var (@vars) {
        _writeDebug("... unsetting preference $var, prio=$record->{prio}");
        $meta->remove('PREFERENCE', $var);
      }
    }
  }

  return $meta;
}

sub handleSetVar {
  my ($this, $session, $params, $topic, $web) = @_;

  #_writeDebug("handleSetVar(".$params->stringify().")");

  $this->addRule(ACTION_SET,
    var => ($params->{_DEFAULT} || $params->{var}),
    value => ($params->{value} // ''),
    type => ($params->{type} || 'Local'),
    field => $params->{field},
    regex => ($params->{match} // $params->{matches} // $params->{regex} // '.*'),
    prio => 1,
  );

  return '';
}

sub handleGetVar {
  my ($this, $session, $params, $topic, $web) = @_;

  my $theTopic = $params->{topic} || $topic;
  my $theWeb = $params->{web} || $web;
  my $theVar = $params->{_DEFAULT};
  my $theFormat = $params->{format};
  my $theHeader = $params->{header} // '';
  my $theFooter = $params->{footer} // '';
  my $theSep = $params->{separator};
  my $theType = $params->{type} || 'PREFERENCE';
  my $theSort = $params->{sort} || 'off';
  my $theDefault = $params->{default} // '';
  my $theScope = $params->{scope} || 'topic'; # global, web, user, session, topic
  
  $theFormat = '$value' unless defined $theFormat;
  $theSep = ', ' unless defined $theSep;

  ($theWeb, $theTopic) = Foswiki::Func::normalizeWebTopicName($theWeb, $theTopic);

  my @result;
  my @metas;
  my $wikiName = Foswiki::Func::getWikiName();

  #_writeDebug("handleGetVar - topic=$theWeb.$theTopic, wikiName=$wikiName, scope=$theScope, type=$theType, var=$theVar");

  # get meta
  if ($theScope eq 'user') {
    ($theWeb, $theTopic) = Foswiki::Func::normalizeWebTopicName($Foswiki::cfg{UsersWebName}, $wikiName);
    $theScope = 'topic';
  }
  if ($theScope eq 'global') {
    my $value = getGlobalVar($theVar);
    if (defined $value) {
      my $meta = {
        name=> $theVar,
        title=> $theVar,
        value=> $value,
        type => 'Global',
      };
      push @metas, $meta;
    }
  } elsif ($theScope eq 'topic') {
    my ($meta, $text) = Foswiki::Func::readTopic($theWeb, $theTopic);
    
    if (!Foswiki::Func::checkAccessPermission("VIEW", $wikiName, $text, $topic, $web, $meta)) {
      _writeDebug("no view access");
      return '';
    }
    @metas = $meta->find($theType);
    #_writeDebug("found ".scalar(@metas)." metas");
  } elsif ($theScope eq 'web') {
    my $value = Foswiki::Func::getPreferencesValue($theVar, $theWeb);
    $value = getGlobalVar($theVar) unless defined $value;
    if (defined $value) {
      my $meta = {
        name=> $theVar,
        title=> $theVar,
        value=> $value,
        type => 'Global',
      };
      push @metas, $meta;
    }
  } elsif ($theScope eq 'session') {
    my @keys = Foswiki::Func::getSessionKeys();
    foreach my $key (@keys) {
      next if $key =~ /^_/;
      my $value = Foswiki::Func::getSessionValue($key);
      next unless defined $value;
      push @metas, {
        name=> $key,
        title=> $key,
        value=> $value,
        type=> 'Session',
      };
    }
  }

  return $theDefault unless @metas;

  # preprocess
  if ($theSort eq 'on') {
    @metas = sort {$a->{name} cmp $b->{name}} @metas;
  }

  # filter and format
  foreach my $meta (@metas) {
    if ($theVar && $meta->{name} =~ /$theVar/) {
      push @result, _expandVariables($theFormat, %$meta);
    }
  }
  return $theDefault unless @result;

  return $theHeader.join($theSep, @result).$theFooter;
}

sub getGlobalVar {
  my $theVar = shift;

  my ($sitePrefsWeb, $sitePrefsTopic) = Foswiki::Func::normalizeWebTopicName($Foswiki::cfg{UsersWebName}, $Foswiki::cfg{LocalSitePreferences});
  Foswiki::Func::pushTopicContext($sitePrefsWeb, $sitePrefsTopic);
  my $value = Foswiki::Func::getPreferencesValue($theVar);
  Foswiki::Func::popTopicContext();
  return $value;
}

sub handleUnsetVar {
  my ($this, $session, $params, $topic, $web) = @_;

  _writeDebug("handleUnsetVar(".$params->stringify().")");

  $this->addRule(ACTION_UNSET,
    var => ($params->{_DEFAULT} || $params->{var}),
    field => $params->{field},
    regex => ($params->{match} // $params->{matches} // $params->{regex} // '.*'),
    prio => 1,
  );

  return '';
}

sub handleDebugRules {
  my ($this, $session, $params, $topic, $web) = @_;

  #_writeDebug("handleDebugRules(".$params->stringify().")");
  
  my $result = '| *Action* | *Type* | *Variable* | *Value* | *Property* | *Match* |'."\n";
  foreach my $record (@{$this->{rules}}) {
    my $format = $record->{format} // $record->{value} // '&nbsp';
    my $field = $record->{field} // 'text';

    $result .= '|'.($record->{action}?'set':'unset');
    $result .= '|'.$record->{type},
    $result .= '|'.$record->{var};
    $result .= '|'.$format;
    $result .= '|'.$field;
    $result .= '|'.$record->{regex};
    $result .= "|\n";
  }

  return $result;
}

sub readTemplate {
  my ($this, $template) = @_;

  unless (defined $this->{_template}{$template}) {
    $this->{_template}{$template} = Foswiki::Func::readTemplate($template);
  }

  return $this->{_template}{$template};
}

sub handleBeforeSave {
  my ($this, $text, $topic, $web, $meta) = @_;

  return if $this->{_insideBeforeSaveHandler};
  $this->{_insideBeforeSaveHandler} = 1;
  _writeDebug("handleBeforeSave($web.$topic)");

  # get the rules NOW
  my $request = Foswiki::Func::getRequestObject();

  my $viewTemplate = Foswiki::Func::getPreferencesValue('VIEW_TEMPLATE');
  $viewTemplate = $request->param("template") unless $viewTemplate;

  #_writeDebug("viewTemplate=".($viewTemplate//''));

  my $tmpl;
  $tmpl = $this->readTemplate($viewTemplate) if $viewTemplate;
  $tmpl = $this->readTemplate('view') unless $tmpl;

  if ($tmpl && $tmpl =~ /\%TEXT%/) {
    $tmpl =~ s/\%TEXT%/$text/g;
  }

  # Item12196: expand only view template if $text isn't included, similar to
  # how Foswiki::UI::View renders pages
  $text = $tmpl;

  # Disable most macros in the text... we only care about those that probably bring in a [GET,SET,UNSET,DEL]VAR
  # TODO: can we perform all INCLUDEs and DBCALLs only before disabling everything else?
  $text =~ s/%((?!(GETVAR|SETVAR|DELVAR|UNSETVAR))$Foswiki::regex{tagNameRegex}(\{.*?\})?)%/%<nop>$1%/gms;

  #_writeDebug("text=$text\n");

  $text = Foswiki::Func::expandCommonVariables($text, $topic, $web) if $text =~ /%/;

  # create rules from Set+VARNAME, Local+VARNAME, Unset+VARNAME and Default+VARNAME urlparams
  #if ($Foswiki::Plugins::VERSION < 2.2) {
    foreach my $key ($request->param()) {

      next unless $key =~ /^(Local|Set|Unset)\+(.*)$/;
      my $type = $1;
      my $name = $2;
      my @values = $request->multi_param($key);
      next unless @values;
      @values = grep {!/^$/} grep {defined($_)} @values if @values > 1;
      my $value = join(", ", @values);
      _writeDebug("key=$key, value=$value");

      # convert a set to an unset if that's already default
      if ($type =~ /Local|Set/) {
        my @defaultValues = $request->multi_param("Default+$name");
        if (@defaultValues) {
          @defaultValues = grep {!/^$/} @defaultValues if @defaultValues > 1;
          my $defaultValue = join(', ', @defaultValues);
          if ($defaultValue eq $value) {
            $type = 'Unset';
            _writeDebug("found set to default/undef ... unsetting ".$name);
          }
        }
      }

      # create a rule
      if ($type eq 'Unset') {
        $this->addRule(ACTION_UNSET,
          var => $name,
          prio => 2,
        );
      } else {
        $this->addRule(ACTION_SET,
          var => $name,
          value => $value,
          type => $type,
          prio => 2,
        );
      }
    }
  #}

  # execute rules in the given order
  $this->applyRules($web, $topic, $meta, $text);

  $this->{_insideBeforeSaveHandler} = 0;
}

# static
sub _expandVariables {
  my ($theFormat, %params) = @_;

  return '' unless defined $theFormat;

  my $mixedAlphaNum = Foswiki::Func::getRegularExpression('mixedAlphaNum');
  
  foreach my $key (keys %params) {
    next if $key =~ /^_/;
    my $val = $params{$key} // '';
    $theFormat =~ s/\$$key\b/$val/g;
  }
  $theFormat =~ s/\$perce?nt/\%/g;
  $theFormat =~ s/\$dollar/\$/g;
  $theFormat =~ s/\$nop//g;
  $theFormat =~ s/\$n([^$mixedAlphaNum]|$)/\n$1/g;

  return $theFormat;
}

sub _writeDebug {
  #Foswiki::Func::writeDebug("- SetVariablePlugin - ".$_[0]) if TRACE;
  print STDERR "- SetVariablePlugin - ".$_[0]."\n" if TRACE;
}


1;
