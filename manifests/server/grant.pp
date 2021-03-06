# Define for granting permissions to roles. See README.md for more details.
define postgresql::server::grant (
  $role,
  $db,
  $privilege   = undef,
  $object_type = 'database',
  $object_name = $db,
  $psql_db     = $postgresql::server::default_database,
  $psql_user   = $postgresql::server::user,
  $port        = $postgresql::server::port
) {
  $group     = $postgresql::server::group
  $psql_path = $postgresql::server::psql_path

  ## Munge the input values
  $_object_type = upcase($object_type)
  $_privilege   = upcase($privilege)

  ## Validate that the object type is known
  validate_string($_object_type,
    #'COLUMN',
    'DATABASE',
    #'FOREIGN SERVER',
    #'FOREIGN DATA WRAPPER',
    #'FUNCTION',
    #'PROCEDURAL LANGUAGE',
    'SCHEMA',
    #'SEQUENCE',
    'TABLE',
    'ALL TABLES IN SCHEMA',
    #'TABLESPACE',
    #'VIEW',
  )
  # You can use ALL TABLES IN SCHEMA by passing schema_name to object_name

  ## Validate that the object type's privilege is acceptable
  # TODO: this is a terrible hack; if they pass "ALL" as the desired privilege,
  #  we need a way to test for it--and has_database_privilege does not
  #  recognize 'ALL' as a valid privilege name. So we probably need to
  #  hard-code a mapping between 'ALL' and the list of actual privileges that
  #  it entails, and loop over them to check them.  That sort of thing will
  #  probably need to wait until we port this over to ruby, so, for now, we're
  #  just going to assume that if they have "CREATE" privileges on a database,
  #  then they have "ALL".  (I told you that it was terrible!)
  case $_object_type {
    'DATABASE': {
      $unless_privilege = $_privilege ? {
        'ALL'            => 'CREATE',
        'ALL PRIVILEGES' => 'CREATE',
        default          => $_privilege,
      }
      validate_string($unless_privilege,'CREATE','CONNECT','TEMPORARY','TEMP',
        'ALL','ALL PRIVILEGES')
      $unless_function = 'has_database_privilege'
      $on_db = $psql_db
    }
    'SCHEMA': {
      $unless_privilege = $_privilege ? {
        'ALL'            => 'CREATE',
        'ALL PRIVILEGES' => 'CREATE',
        default          => $_privilege,
      }
      validate_string($_privilege, 'CREATE', 'USAGE', 'ALL', 'ALL PRIVILEGES')
      $unless_function = 'has_schema_privilege'
      $on_db = $db
    }
    'TABLE': {
      $unless_privilege = $_privilege ? {
        'ALL'   => 'INSERT',
        default => $_privilege,
      }
      validate_string($unless_privilege,'SELECT','INSERT','UPDATE','DELETE',
        'TRUNCATE','REFERENCES','TRIGGER','ALL','ALL PRIVILEGES')
      $unless_function = 'has_table_privilege'
      $on_db = $db
    }
    'ALL TABLES IN SCHEMA': {
      validate_string($_privilege, 'SELECT', 'INSERT', 'UPDATE', 'REFERENCES',
        'ALL', 'ALL PRIVILEGES')
      $unless_function = false # There is no way to test it simply
      $on_db = $db
    }
    default: {
      fail("Missing privilege validation for object type ${_object_type}")
    }
  }

  # This is used to give grant to "schemaname"."tablename"
  # If you need such grant, use:
  # postgresql::grant { 'table:foo':
  #   role        => 'joe',
  #   …
  #   object_type => 'TABLE',
  #   object_name => [$schema, $table],
  # }
  if is_array($object_name) {
    $_togrant_object = join($object_name, '"."')
    # Never put double quotes into has_*_privilege function
    $_granted_object = join($object_name, '.')
  } else {
    $_granted_object = $object_name
    $_togrant_object = $object_name
  }

  $_unless = $unless_function ? {
      false   => undef,
      default => "SELECT 1 WHERE ${unless_function}('${role}',
                  '${_granted_object}', '${unless_privilege}')",
  }

  $grant_cmd = "GRANT ${_privilege} ON ${_object_type} \"${_togrant_object}\" TO
      \"${role}\""
  postgresql_psql { "grant:${name}":
    command    => $grant_cmd,
    db         => $on_db,
    port       => $port,
    psql_user  => $psql_user,
    psql_group => $group,
    psql_path  => $psql_path,
    unless     => $_unless,
    require    => Class['postgresql::server']
  }

  if($role != undef and defined(Postgresql::Server::Role[$role])) {
    Postgresql::Server::Role[$role]->Postgresql_psql["grant:${name}"]
  }

  if($db != undef and defined(Postgresql::Server::Database[$db])) {
    Postgresql::Server::Database[$db]->Postgresql_psql["grant:${name}"]
  }
}
