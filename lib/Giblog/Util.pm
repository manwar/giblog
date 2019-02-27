package Giblog::Util;

use strict;
use warnings;

my $inline_elements_re = qr/^<(span|em|strong|abbr|acronym|dfn|q|cite|sup|sub|code|var|kbd|samp|bdo|font|big|small|b|i|s|strike|u|tt|a|label|object|applet|iframe|button|textarea|select|basefont|img|br|input|script|map)\b/;

sub parse_giblog_syntax {
  my ($giblog, $data) = @_;
  
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
  my ($giblog, $data) = @_;

  my $config = $giblog->config;

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
  my ($giblog, $data) = @_;

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
  my ($giblog, $data) = @_;

  my $content = $data->{content};
  
  if ($content =~ m|class="description"[^>]*?>([^<]*?)<|) {
    my $description = $1;
    unless (defined $data->{'description'}) {
      $data->{'description'} = $description;
    }
  }
}

sub parse_description_from_first_p_tag {
  my ($giblog, $data) = @_;

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
  my ($giblog, $data) = @_;

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
  my ($giblog, $data) = @_;

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
  my ($giblog, $data) = @_;

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
  my ($giblog, $data) = @_;
  
  my $meta = $data->{meta};
  
  # Title
  my $title = $data->{title};
  if (defined $title) {
    $meta .= "\n<title>$title</title>\n";
  }
  
  $data->{meta} = $meta;
}

sub add_meta_description {
  my ($giblog, $data) = @_;
  
  my $meta = $data->{meta};
  
  # Title
  my $description = $data->{description};
  if (defined $description) {
    $meta .= qq(\n<meta name="description" content="$description">\n);
  }
  
  $data->{meta} = $meta;
}

sub prepare_wrap_content {
  my ($giblog, $data) = @_;
  
  my $common_meta_file = $giblog->rel_file('templates/common/meta.html');
  my $common_meta_content = $giblog->slurp_file($common_meta_file);
  $data->{meta} = $common_meta_content;

  my $common_header_file = $giblog->rel_file('templates/common/header.html');
  my $common_header_content = $giblog->slurp_file($common_header_file);
  $data->{header} = $common_header_content;

  my $common_footer_file = $giblog->rel_file('templates/common/footer.html');
  my $common_footer_content = $giblog->slurp_file($common_footer_file);
  $data->{footer} = $common_footer_content;

  my $common_side_file = $giblog->rel_file('templates/common/side.html');
  my $common_side_content = $giblog->slurp_file($common_side_file);
  $data->{side} = $common_side_content;

  my $common_top_file = $giblog->rel_file('templates/common/top.html');
  my $common_top_content = $giblog->slurp_file($common_top_file);
  $data->{top} = $common_top_content;

  my $common_bottom_file = $giblog->rel_file('templates/common/bottom.html');
  my $common_bottom_content = $giblog->slurp_file($common_bottom_file);
  $data->{bottom} = $common_bottom_content;
}

1;
