package Giblog::Command::build;

use base 'Giblog::Command';

use strict;
use warnings;

use File::Basename 'basename';

sub run {
  my ($self, @args) = @_;
  
  # API
  my $api = $self->api;
  
  # Read config
  my $config = $api->read_config;
  
  # Get files in templates directory
  my $files = $api->get_templates_files;
  
  for my $file (@$files) {
    
    my $data = {file => $file};
    
    # Get content from file in templates directory
    $api->get_content($data);

    # Parse Giblog syntax
    $api->parse_giblog_syntax($data);

    # Parse title
    $api->parse_title_from_first_h_tag($data);

    # Add page link
    $api->add_page_link_to_first_h_tag($data, {root => 'index.html'});

    # Parse description
    $api->parse_description_from_first_p_tag($data);

    # Read common templates
    $api->read_common_templates($data);
    
    # Add meta title
    $api->add_meta_title($data);

    # Add meta description
    $api->add_meta_description($data);

    # Build entry html
    $api->build_entry($data);
    
    # Build whole html
    $api->build_html($data);
    
    # Write to public file
    $api->write_to_public_file($data);
  }

  $self->create_index;
  $self->create_list;
}

# Create latest entries page
sub create_index {
  my $self = shift;
  
  my $api = $self->api;

  my $config = $api->config;

  my @template_files = glob $api->rel_file('templates/blog/*');
  
  @template_files = reverse sort @template_files;
  
  my $before_year = 0;
  my @entry_contents;
  for (my $i = 0; $i < 7; $i++) {
    my $template_file = $template_files[$i];
    
    last unless defined $template_file;
    
    my $base_name = basename $template_file;
    my ($year, $month, $mday) = $base_name =~ /^(\d{4})(\d{2})(\d{2})/;
    
    my $content = $api->slurp_file($template_file);
    my $data = {content => $content, file => "blog/$base_name"};
    
    # Parse Giblog syntax
    $api->parse_giblog_syntax($data);

    # Add page link
    $api->add_page_link_to_first_h_tag($data, {root => 'index.html'});
    
    $data->{content} = <<"EOS";
<div style="text-align:right;color:#999">${year}/${month}/${mday}</div>
$data->{content}
EOS
    
    # Build entry html
    $data->{top} = '';
    $data->{bottom} = '';
    $api->build_entry($data);
    
    push @entry_contents, $data->{content};
  }
  
  my $latest_content = join("\n", @entry_contents);
  my $data = {content => $latest_content};

  $data->{content} .= qq(\n<div style="text-align:center"><a href="/list.html">Before Days</a></div>);
  
  # Title
  $data->{title} = $config->{site_title};
  
  # Description
  $data->{description} = 'Site description';

  # Read common templates
  $api->read_common_templates($data);

  # Add meta title
  $api->add_meta_title($data);

  # Add meta description
  $api->add_meta_description($data);

  # Build whole html
  $api->build_html($data);
  
  my $html = $data->{content};

  my $latest_file = $api->rel_file('public/index.html');
  $api->write_to_file($latest_file, $html);
}

# Create all entry list page
sub create_list {
  my $self = shift;
  
  # API
  my $api = $self->api;
  
  # Config
  my $config = $api->config;
  
  # Template files
  my @template_files = glob $api->rel_file('templates/blog/*');
  @template_files = reverse sort @template_files;
  
  my $list_content;
  $list_content = <<'EOS';
<h2>Entries</h2>
EOS

  $list_content .= "<ul>\n";
  my $before_year = 0;
  for my $template_file (@template_files) {
    my $base_name = basename $template_file;
    
    my ($year, $month, $mday) = $base_name =~ /^(\d{4})(\d{2})(\d{2})/;
    $month =~ s/^0//;
    $mday =~ s/^0//;
    if ($year != $before_year) {
      $list_content .= <<"EOS";
  <li style="list-style:none;">
    <b>${year}</b>
  </li>
EOS
    }
    $before_year = $year;
    
    my $file = "blog/$base_name";
    
    my $data = {file => $file};
    
    $api->get_content($data);
    
    $api->parse_title_from_first_h_tag($data);
    
    my $title = $data->{title};
    
    my $path;
    if ($file eq 'index.html') {
      $path = '/';
    }
    else {
      $path = "/$file";
    }
    
    unless(defined $title) {
      $title = 'No title';
    }
    
    $list_content .= <<"EOS";
  <li style="list-style:none">
    $month/$mday <a href="$path">$title</a>
  </li>
EOS
  }

  $list_content .= "</ul>\n";
  
  my $data = {content => $list_content, file => 'list.html'};

  # Add page link
  $api->add_page_link_to_first_h_tag($data);

  # Title
  $data->{title} = "Entries - $config->{site_title}";
  
  # Description
  $data->{description} = "Entries of $config->{site_title}";

  # Read common templates
  $api->read_common_templates($data);

  # Add meta title
  $api->add_meta_title($data);

  # Add meta description
  $api->add_meta_description($data);
  
  my $site_title = $config->{site_title};
  
  $data->{meta} .= "<title>Entries - $site_title</title>\n";

  # Build entry html
  $api->build_entry($data);
  
  # Build whole html
  $api->build_html($data);
  
  my $html = $data->{content};
  
  my $list_file = $api->rel_file('public/list.html');
  $api->write_to_file($list_file, $html);
}

1;
