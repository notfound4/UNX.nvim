-- lua/UNX/ui/view/query.lua
local M = {}

M.cpp = [[
  (access_specifier) @access_label
  (unreal_class_declaration name: (_) @class_name) @definition.uclass
  (unreal_struct_declaration name: (_) @struct_name) @definition.ustruct
  (unreal_enum_declaration name: (_) @enum_name) @definition.uenum
  (class_specifier name: (_) @class_name) @definition.class
  (struct_specifier name: (_) @struct_name) @definition.struct

  (function_definition
    declarator: [
      (function_declarator declarator: (_) @func_name)
      (pointer_declarator (function_declarator declarator: (_) @func_name))
      (reference_declarator (function_declarator declarator: (_) @func_name))
      (field_identifier) @func_name
      (identifier) @func_name
      (function_declarator (qualified_identifier scope: (_) @impl_class name: (_) @func_name))
      (pointer_declarator (function_declarator (qualified_identifier scope: (_) @impl_class name: (_) @func_name)))
      (reference_declarator (function_declarator (qualified_identifier scope: (_) @impl_class name: (_) @func_name)))
    ]
  ) @definition.function

  (field_declaration
    declarator: [
      (function_declarator declarator: (_) @func_name)
      (pointer_declarator (function_declarator declarator: (_) @func_name))
      (reference_declarator (function_declarator declarator: (_) @func_name))
    ]
  ) @definition.method

  (declaration
    (function_declarator
      declarator: (_) @func_name
    )
  ) @definition.method

  (field_declaration
    declarator: [
      (field_identifier) @field_name
      (pointer_declarator declarator: (_) @field_name)
      (pointer_declarator (_) @field_name)
      (array_declarator declarator: (_) @field_name)
      (array_declarator (_) @field_name)
      (reference_declarator (_) @field_name)
    ]
  ) @definition.field
]]

return M
