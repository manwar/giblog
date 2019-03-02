package Giblog::API;

use strict;
use warnings;
use File::Find 'find';
use File::Basename 'dirname', 'basename';
use File::Path 'mkpath';
use Carp 'confess';
use Encode 'encode', 'decode';

sub new {
  my $class = shift;
  
  my $self = {@_};
  
  return bless $self, $class;
}

sub read_config {
  my $self = shift;
  
  my $giblog = $self->giblog;
  
  unless (defined $giblog->{config}) {
    my $config_file = $self->rel_file('giblog.conf');
    
    my $config_content = $self->slurp_file($config_file);
    
    my $config = eval $config_content
      or confess "Can't parse config file \"$config_file\"";
    
    $giblog->{config} = $config;
  }
}

sub config { shift->giblog->config }
sub giblog_dir { shift->giblog->giblog_dir };

sub rel_file {
  my ($self, $file) = @_;
  
  my $giblog_dir = $self->giblog->giblog_dir;
  
  if (defined $giblog_dir) {
    return "$giblog_dir/$file";
  }
  else {
    return $file;
  }
}

sub create_dir {
  my ($self, $dir) = @_;
  mkdir $dir
    or confess "Can't create directory \"$dir\": $!";
}

sub create_file {
  my ($self, $file) = @_;
  open my $fh, '>', $file
    or confess "Can't create file \"$file\": $!";
}

sub write_to_file {
  my ($self, $file, $content) = @_;
  open my $fh, '>', $file
    or confess "Can't create file \"$file\": $!";
  
  print $fh encode('UTF-8', $content);
}

sub slurp_file {
  my ($self, $file) = @_;

  open my $fh, '<', $file
    or confess "Can't read file \"$file\": $!";
  
  my $content = do { local $/; <$fh> };
  $content = decode('UTF-8', $content);
  
  return $content;
}

sub command_rel_file {
  my ($self, $command, $rel_file) = @_;
  
  my $command_rel_path = ref $command;
  $command_rel_path =~ s/::/\//g;
  $command_rel_path .= '.pm';
  
  my $command_path = $INC{$command_rel_path};
  my $command_dir = $command_path;
  $command_dir =~ s/\.pm$//;
  
  my $file = "$command_dir/$rel_file";
  
  return $file;
}

sub giblog { shift->{giblog} }

sub build_all {
  my ($self, $cb) = @_;
  
  my $templates_dir = $self->rel_file('templates');
  my $public_dir = $self->rel_file('public');
  
  # Get template files
  my @template_rel_files;
  find(
    {
      wanted => sub {
        my $template_file = $File::Find::name;
        
        # Skip directory
        return unless -f $template_file;

        # Skip common files
        return if $template_file =~ /^\Q$templates_dir\/common/;
        
        my $template_file_base = $_;
        
        # Skip hidden file
        return if $template_file_base =~ /^\./;
        
        my $template_rel_file = $template_file;
        $template_rel_file =~ s/^$templates_dir//;
        $template_rel_file =~ s/^[\\\/]//;
        $template_rel_file = "templates/$template_rel_file";
        
        push @template_rel_files, $template_rel_file;
      },
      no_chdir => 1,
    },
    $templates_dir
  );
  
  for my $template_rel_file (@template_rel_files) {
    my $template_file = $self->rel_file($template_rel_file);
    my $content = $self->slurp_file($template_file);
    
    my $path = $template_rel_file;
    $path =~ s|^templates||;
    if ($path eq '/index.html') {
      $path = '/';
    }
    
    my $data = {
      content => $content,
      path => $path,
    };

    # Build html
    $cb->($self, $data);
    
    my $html = $data->{content};
    
    # public file
    my $public_rel_file = $template_rel_file;
    $public_rel_file =~ s/^templates/public/;
    my $public_file = $self->rel_file("$public_rel_file");
    my $public_dir = dirname $public_file;
    mkpath $public_dir;
    
    # Write to public file
    $self->write_to_file($public_file, $html);
  }
}

my $inline_elements_re = qr/^<(span|em|strong|abbr|acronym|dfn|q|cite|sup|sub|code|var|kbd|samp|bdo|font|big|small|b|i|s|strike|u|tt|a|label|object|applet|iframe|button|textarea|select|basefont|img|br|input|script|map)\b/;

sub parse_giblog_syntax {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;
  
  my $content = $data->{content};

  # Normalize line break;
  $content =~ s/\x0D\x0A|\x0D|\x0A/\n/g;
  
  # Parse Giblog syntax
  my @lines = split /\n/, $content;
  my $pre_start;
  $content = '';
  my $bread_end;
  for my $line (@lines) {
    my $original_line = $line;
    
    # Pre end
    if ($line =~ m|^</pre\b|) {
      $pre_start = 0;
    }
    
    # Escape >, < in pre tag
    if ($pre_start) {
      $line =~ s/>/&gt;/g;
      $line =~ s/</&lt;/g;
      $content .= "$line\n";
    }
    else {
      # If start with inline tag, wrap p
      if ($line =~ $inline_elements_re) {
        $content .= "<p>\n  $line\n</p>\n";
      }
      # If start with space or tab or not inline tag, it is raw line
      elsif ($line =~ /^[ \t\<]/) {
        $content .= "$line\n";
      }
      # If line have length, wrap p
      else {
        if (length $line) {
          $content .= "<p>\n  $line\n</p>\n";
        }
      }
    }

    # Pre start
    if ($original_line =~ m|^<pre\b|) {
      $pre_start = 1
    }
  }
  
  $data->{content} = $content;
}

sub parse_title {
  my ($self, $data) = @_;
  
  my $config = $self->config;

  my $content = $data->{content};
  
  if ($content =~ m|class="title"[^>]*?>([^<]*?)<|) {
    my $page_title = $1;
    unless (defined $data->{'title'}) {
      # Add site title after title
      my $site_title = $config->{site_title};
      my $title;
      if (length $page_title) {
        if (length $site_title) {
          $title = "$page_title - $site_title";
        }
        else {
          $title = $page_title;
        }
      }
      else {
        if (length $site_title) {
          $title = $site_title;
        }
        else {
          $title = '';
        }
      }
      $data->{title} = $title;
    }
  }
}

sub add_page_link {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;

  my $content = $data->{content};
  
  # Add page link
  my $path = $data->{path};
  my $path_tmp = $path;
  unless (defined $path_tmp) {
    $path_tmp = '';
  }
  $content =~ s|class="title"[^>]*?>([^<]*?)<|class="title"><a href="$path_tmp">$1</a><|;

  $data->{'content'} = $content;
}

sub parse_description {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;

  my $content = $data->{content};
  
  if ($content =~ m|class="description"[^>]*?>([^<]*?)<|) {
    my $description = $1;
    unless (defined $data->{'description'}) {
      $data->{'description'} = $description;
    }
  }
}

sub parse_description_from_first_p_tag {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;

  my $content = $data->{content};
  
  # Create description from first p tag
  unless (defined $data->{'description'}) {
    if ($content =~ m|<\s?p\b[^>]*?>(.*?)<\s?/\s?p\s?>|s) {
      my $description = $1;
      # remove tag
      $description =~ s/<.*?>//g;
      
      # trim space
      $description =~ s/^\s+//;
      $description =~ s/\s+$//;
      
      $data->{'description'} = $description;
    }
  }
}

sub parse_keywords {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;

  my $content = $data->{content};

  # keywords
  if ($content =~ m|class="keywords"[^>]*?>([^<]*?)<|) {
    my $keywords = $1;
    unless (defined $data->{'keywords'}) {
      $data->{'keywords'} = $1;
    }
  }
}

sub parse_first_img_src {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;

  my $content = $data->{content};
  
  # image
  if ($content =~ /<\s*img\b.*?\bsrc\s*=\s*"([^"]*?)"/s) {
    my $image = $1;
    unless (defined $data->{'image'}) {
      $data->{'image'} = $image;
    }
  }
}

sub wrap_content {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;

  my $content = <<"EOS";
<!DOCTYPE html>
<html>
  <head>
    $data->{meta}
  </head>
  <body>
    <div class="container">
      <div class="header">
        $data->{header}
      </div>
      <div class="main">
        <div class="entry">
          <div class="top">
            $data->{top}
          </div>
          <div class="content">
            $data->{content}
          </div>
          <div class="bottom">
            $data->{bottom}
          </div>
        </div>
        <div class="side">
          $data->{side}
        </div>
      </div>
      <div class="footer">
        $data->{footer}
      </div>
    </div>
  </body>
</html>
EOS
  
  $data->{content} = $content;
}

sub add_meta_title {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;
  
  my $meta = $data->{meta};
  
  # Title
  my $title = $data->{title};
  if (defined $title) {
    $meta .= "\n<title>$title</title>\n";
  }
  
  $data->{meta} = $meta;
}

sub add_meta_description {
  my ($self, $data) = @_;
  
  my $giblog = $self->giblog;
  
  my $meta = $data->{meta};
  
  # Title
  my $description = $data->{description};
  if (defined $description) {
    $meta .= qq(\n<meta name="description" content="$description">\n);
  }
  
  $data->{meta} = $meta;
}

sub prepare_wrap_content {
  my ($self, $data) = @_;
  
  my $common_meta_file = $self->rel_file('templates/common/meta.html');
  my $common_meta_content = $self->slurp_file($common_meta_file);
  $data->{meta} = $common_meta_content;

  my $common_header_file = $self->rel_file('templates/common/header.html');
  my $common_header_content = $self->slurp_file($common_header_file);
  $data->{header} = $common_header_content;

  my $common_footer_file = $self->rel_file('templates/common/footer.html');
  my $common_footer_content = $self->slurp_file($common_footer_file);
  $data->{footer} = $common_footer_content;

  my $common_side_file = $self->rel_file('templates/common/side.html');
  my $common_side_content = $self->slurp_file($common_side_file);
  $data->{side} = $common_side_content;

  my $common_top_file = $self->rel_file('templates/common/top.html');
  my $common_top_content = $self->slurp_file($common_top_file);
  $data->{top} = $common_top_content;

  my $common_bottom_file = $self->rel_file('templates/common/bottom.html');
  my $common_bottom_content = $self->slurp_file($common_bottom_file);
  $data->{bottom} = $common_bottom_content;
}

1;