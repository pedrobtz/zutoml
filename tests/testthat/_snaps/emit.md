# emission is deterministic: a checked-in document

    Code
      cat(toml_emit(x))
    Output
      title = "zutoml"
      version = 1
      ratio = 0.1
      big = 9007199254740993
      flags = [true, false]
      when = 1979-05-27T07:32:00.250Z
      day = 1979-05-27
      at = 07:32:00
      text = """
      two
      lines"""
      empty = []
      one = ["x"]
      
      [owner]
      name = "Tom"
      "quoted key" = 1
      
      [owner.nested]
      deep = true
      
      [[rows]]
      a = 1
      
      [[rows]]
      a = 2
      b = [1.5, 2]

