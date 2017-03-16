{% from 'emacs/settings.sls' import emacs with context %}

{%- if emacs.from_pkg == True %}
install-emacs:
  pkg.installed:
    - pkgs:
        - emacs
{% else %}


## Pull down a github release of the desired version
emacs-fetch-release:
  archive.extracted:
    - name: {{ emacs.build_dir }}
    - source: {{ emacs.archive_url % emacs }}
    - archive_format: tar
    - source_hash: {{ emacs.hash }}
    - user: root
    - group: root
    - if_missing: {{ emacs.build_dir }}/{{ emacs.name }}
      
  file.rename:
    - name: {{ emacs.build_dir }}/{{ emacs.name }}
    - source: {{ emacs.build_dir }}/emacs-{{ emacs.name }}
    - force: true
    - require:
        - archive: emacs-fetch-release
          
emacs-deps:
  cmd.run:
    - name: |
        apt-get -y build-dep emacs24
    - shell: /bin/bash
    - require:
        - pkg: emacs-deps
  pkg.installed:
    - ignore_installed: true
    - reload_modules: true
    - pkgs:
        - git
        - build-essential
        - texinfo
        - automake

emacs-create-directories:
  file.directory:
    - names:
        - {{ emacs.prefix }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: true

emacs-autogen-source:
  cmd.run:
    - name: |
        cd {{ emacs.build_dir }}/{{ emacs.name }}
        ./autogen.sh
    - shell: /bin/bash
    - cwd: {{ emacs.build_dir }}/{{ emacs.name }}
    - unless:
        - test -x {{ emacs.real_home }}/bin/emacs-{{ emacs.version }}
    - require:
        - file: emacs-fetch-release
        - pkg: emacs-deps

emacs-configure:
  # I couldn't figure out how to run `build-dep` using a state so I poked that bit
  # into the build command.  If all goes well, we should have an emacs install by
  # the time the water for your locally-sourced artisinal chai has had time to boil.
  #
  # :NOTE: Someone may want to run the X version and it is disabled here explicitly because
  #   building the X version took even longer. These flags should probably come from a pillar
  #
  # :NOTE: This should really be broken up into separate steps since configre and make can each take
  #   several minutes to complete on the smaller systems. 
  cmd.run:
    - name: |
        cd {{ emacs.build_dir }}/{{ emacs.name }}
        ./configure --prefix={{ emacs.real_home }} --with-x-toolkit=no --without-x
    - shell: /bin/bash
    - timeout: 3000
    - unless:
        - test -x {{ emacs.real_home }}/bin/emacs-{{ emacs.version }}

    - cwd: {{ emacs.build_dir }}
    - require:
        - file: emacs-fetch-release
        - file: emacs-create-directories
        - cmd: emacs-deps
        - cmd: emacs-autogen-source
          
emacs-make:
  cmd.run:
    - name: |
        cd {{ emacs.build_dir }}/{{ emacs.name }}        
        make
    - shell: /bin/bash
    - timeout: 3000
    - unless:
        - test -x {{ emacs.real_home }}/bin/emacs-{{ emacs.version }}

    - cwd: {{ emacs.build_dir }}
    - require:
        - cmd: emacs-configure

emacs-make-install:
  cmd.run:
    - name: |
        cd {{ emacs.build_dir }}/{{ emacs.name }}        
        make install
    - shell: /bin/bash
    - timeout: 3000
    - unless:
        - test -x {{ emacs.real_home }}/bin/emacs-{{ emacs.version }}

    - cwd: {{ emacs.build_dir }}
    - require:
        - cmd: emacs-make

emacs-alternatives:
  # should end up something like /usr/lib/emacs pointing to this version
  alternatives.install:
    - name: emacs-home-link
    - link: {{ emacs.alt_home }}
    - path: {{ emacs.real_home }}
    - priority: 30
    - require:
        - cmd: emacs-make-install
        - cmd: emacs-make
  
# the above build has created binaries in {{ emacs.bin_dir }} and in order to
# preserve the ability to switch between versions, sym-links are created in /usr/bin
{%- for tag in ['ctags','ebrowse','emacsclient','etags'] %}
emacs-link-{{ tag }}:
  alternatives.install:
    - name: {{ tag }}
    - link: /usr/bin/{{ tag }}
    - path: {{ emacs.bin_dir }}/{{ tag }}
    - priority: 999
    - require:
        - cmd: emacs-make-install
        - alternatives: emacs-alternatives
{% endfor %}

# The emacs binary is built with the version baked into the name (emacs-25.0.91)
# create a sym-link with a high priority at `/usr/bin/emacs`
emacs-post-install:
  alternatives.install:
    - name: emacs
    - link: /usr/bin/emacs
    - path: {{ emacs.bin_dir }}/emacs-{{ emacs.version }}
    - priority: 999
    - require:
        - cmd: emacs-make-install        
        - alternatives: emacs-alternatives
{% endif %}
