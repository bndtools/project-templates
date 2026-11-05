use strict;
use warnings;
use File::Find;
use File::Path qw(make_path);
use File::Spec;

my ($templates, $workspace) = @ARGV;
die "usage: templates.pl <templates> <workspace>\n" unless defined $workspace;
my %values = (
    srcDir => 'src/main/java', testSrcDir => 'src/test/java',
    basePackageDir => 'org/bndtools/templates/smoke',
    basePackageName => 'org.bndtools.templates.smoke', javaLevel => '8',
    fileName => 'template-launch.bndrun',
);

sub read_text {
    my ($path) = @_;
    open my $input, '<:raw', $path or die "$path: $!\n";
    local $/;
    return <$input>;
}

sub write_text {
    my ($path, $text) = @_;
    open my $output, '>:raw', $path or die "$path: $!\n";
    print {$output} $text;
    close $output or die "$path: $!\n";
}

sub render {
    my ($source, $destination, $project) = @_;
    $values{projectName} = $project;
    find({no_chdir => 1, wanted => sub {
        my $path = $File::Find::name;
        my $relative = File::Spec->abs2rel($path, $source);
        $relative =~ tr{\\}{/};
        if (-d $path && $relative =~ m{(?:^|/)(?:bin|generated)(?:/|$)}) {
            $File::Find::prune = 1;
            return;
        }
        return if $relative eq '.';
        $relative =~ s/\$([A-Za-z][A-Za-z0-9]*)\$/exists $values{$1} ? $values{$1} : die "unknown path variable: $1\n"/ge;
        my $output = "$destination/$relative";
        if (-d $path) { make_path($output); return; }
        my (undef, $directory) = File::Spec->splitpath($output);
        make_path($directory);
        my $text = read_text($path);
        unless ($text =~ /\x00/) {
            $text =~ s/\$if\(javaLevel\)\$|\$endif\$//g;
            $text =~ s/\$([A-Za-z][A-Za-z0-9]*)\$/exists $values{$1} ? $values{$1} : die "unknown variable $1 in $path\n"/ge;
            $text =~ s/\\\$\{/\${/g;
            die "unrendered conditional in $path\n" if $text =~ /\$(?:if\([^)]+\)|endif)\$/;
        }
        write_text($output, $text);
    }}, $source);
}

for my $name (qw(api app ds integration-test jax-rs jpa-dao servlet)) {
    render("$templates/$name", "$workspace/template-$name", "template-$name");
}
render("$templates/launch/felix-gogo", "$workspace/template-launch-probe", 'template-launch');

for my $relative ('template-app/template-app.bndrun', 'template-ds/launch.bndrun',
                  'template-jax-rs/launch.bndrun', 'template-servlet/launch.bndrun',
                  'template-launch-probe/template-launch.bndrun') {
    my $path = "$workspace/$relative";
    my $text = read_text($path);
    my $count = $text =~ s/^(-runrequires:[ \t]*\\)[ \t]*\r?$/"$1\n\tosgi.identity;filter:='(osgi.identity=template-launch-probe)',\\"/me;
    die "no continuation-style -runrequires in $path\n" unless $count == 1;
    $count = $text =~ s/(-runprovidedcapabilities: \$\{native_capability\})/$1,\\\n\tosgi.ee;osgi.ee=JavaSE;version:Version=1.7.0,\\\n\tosgi.ee;osgi.ee=JavaSE;version:Version=1.8.0/;
    die "no native run capability in $path\n" unless $count == 1;
    if ($relative =~ /jax-rs/) {
        $text =~ s/(osgi.ee;osgi.ee=JavaSE;version:Version=1.8.0)/$1,\\\n\tosgi.implementation;osgi.implementation=osgi.jaxrs;version:Version=1.0.0/;
    }
    write_text($path, $text);
}

for my $name (qw(ds jax-rs servlet)) {
    find({no_chdir => 1, wanted => sub {
        return unless -f $_ && /\.java$/;
        my $text = read_text($_);
        $text =~ s/fail\("Not yet implemented"\);/assertTrue(true);/g;
        write_text($_, $text);
    }}, "$workspace/template-$name/src/test");
}