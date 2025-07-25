defmodule Calex.EncodingTest do
  use ExUnit.Case

  test "encodes iCal keyword list" do
    data = [
      vcalendar: [
        [
          vevent: [
            [
              dtstamp: {"20210727T183739Z", []},
              summary: {"Hello World", []},
              description: {"Here are some notes!", []},
              location: {"", []},
              tzid: {"America/Winnipeg", []},
              sequence: {"0", []},
              uid: {"1C192BA5-A5FE-481F-B111-4D401208070E", []},
              created: {"20210727T183739Z", []},
              dtstart: {"20210728T140000", [tzid: "America/Winnipeg"]},
              dtend: {"20210728T151500", [tzid: "America/Winnipeg"]},
              x_apple_travel_advisory_behavior: {"AUTOMATIC", []},
              transp: {"OPAQUE", []}
            ]
          ]
        ]
      ]
    ]

    assert Calex.encode!(data) ==
             crlf("""
             BEGIN:VCALENDAR
             BEGIN:VEVENT
             DTSTAMP:20210727T183739Z
             SUMMARY:Hello World
             DESCRIPTION:Here are some notes!
             LOCATION:
             TZID:America/Winnipeg
             SEQUENCE:0
             UID:1C192BA5-A5FE-481F-B111-4D401208070E
             CREATED:20210727T183739Z
             DTSTART;TZID=America/Winnipeg:20210728T140000
             DTEND;TZID=America/Winnipeg:20210728T151500
             X-APPLE-TRAVEL-ADVISORY-BEHAVIOR:AUTOMATIC
             TRANSP:OPAQUE
             END:VEVENT
             END:VCALENDAR
             """)
  end

  test "encodes UTC dates" do
    data = [
      vcalendar: [
        [
          vevent: [
            [
              dtstamp: {~U[2021-06-01 00:00:00Z], []}
            ]
          ]
        ]
      ]
    ]

    assert Calex.encode!(data) ==
             crlf("""
             BEGIN:VCALENDAR
             BEGIN:VEVENT
             DTSTAMP:20210601T000000Z
             END:VEVENT
             END:VCALENDAR
             """)
  end

  test "encodes UTC dates to second resolution" do
    data = [
      vcalendar: [
        [
          vevent: [
            [
              dtstamp: {~U[2021-06-01 00:00:00.123Z], []}
            ]
          ]
        ]
      ]
    ]

    assert Calex.encode!(data) ==
             crlf("""
             BEGIN:VCALENDAR
             BEGIN:VEVENT
             DTSTAMP:20210601T000000Z
             END:VEVENT
             END:VCALENDAR
             """)
  end

  test "encodes non-UTC dates" do
    data = [
      vcalendar: [
        [
          vevent: [
            [
              dtstamp: {DateTime.from_naive!(~N[2021-06-01 00:00:00], "America/Chicago"), []}
            ]
          ]
        ]
      ]
    ]

    assert Calex.encode!(data) ==
             crlf("""
             BEGIN:VCALENDAR
             BEGIN:VEVENT
             DTSTAMP;TZID=America/Chicago:20210601T000000
             END:VEVENT
             END:VCALENDAR
             """)
  end

  test "encodes non-UTC dates to second resolution" do
    data = [
      vcalendar: [
        [
          vevent: [
            [
              dtstamp: {DateTime.from_naive!(~N[2021-06-01 00:00:00.123], "America/Chicago"), []}
            ]
          ]
        ]
      ]
    ]

    assert Calex.encode!(data) ==
             crlf("""
             BEGIN:VCALENDAR
             BEGIN:VEVENT
             DTSTAMP;TZID=America/Chicago:20210601T000000
             END:VEVENT
             END:VCALENDAR
             """)
  end

  test "encodes naive datetimes" do
    data = [
      vcalendar: [
        [
          vevent: [
            [
              dtstart: {~N[2021-06-01 00:00:00.123], []}
            ]
          ]
        ]
      ]
    ]

    assert Calex.encode!(data) ==
             crlf("""
             BEGIN:VCALENDAR
             BEGIN:VEVENT
             DTSTART:20210601T000000
             END:VEVENT
             END:VCALENDAR
             """)
  end

  test "encodes dates" do
    data = [
      vcalendar: [
        [
          vevent: [
            [
              dtstamp: {~D[2021-06-01], []}
            ]
          ]
        ]
      ]
    ]

    assert Calex.encode!(data) ==
             crlf("""
             BEGIN:VCALENDAR
             BEGIN:VEVENT
             DTSTAMP;VALUE=DATE:20210601
             END:VEVENT
             END:VCALENDAR
             """)
  end

  test "encodes atom property value" do
    data = [
      vcalendar: [
        [
          vevent: [
            [
              class: {:public, []}
            ]
          ]
        ]
      ]
    ]

    assert Calex.encode!(data) ==
             crlf("""
             BEGIN:VCALENDAR
             BEGIN:VEVENT
             CLASS:PUBLIC
             END:VEVENT
             END:VCALENDAR
             """)
  end

  test "unhandled types are just used as-is" do
    data = [
      vcalendar: [
        [
          vevent: [
            [
              x_unknown: {1, [x_foo: 2]}
            ]
          ]
        ]
      ]
    ]

    assert Calex.encode!(data) ==
             crlf("""
             BEGIN:VCALENDAR
             BEGIN:VEVENT
             X-UNKNOWN;X-FOO=2:1
             END:VEVENT
             END:VCALENDAR
             """)
  end

  test "parameter values are properly escaped" do
    data = [
      vcalendar: [
        [
          vevent: [
            [
              organizer: {
                "mailto:organizer@example.com",
                [
                  cn: ~s(Dwayne "The Rock" \n\nJohnson),
                  sent_by: "mailto:person@example.com",
                  x_comma: "1,2,3",
                  x_semicolon: "1;2;3",
                  x_type: :important
                ]
              }
            ]
          ]
        ]
      ]
    ]

    assert Calex.encode!(data) ==
             crlf("""
             BEGIN:VCALENDAR
             BEGIN:VEVENT
             ORGANIZER;CN=Dwayne 'The Rock' Johnson;SENT-BY="mailto:person@example.com";
              X-COMMA="1,2,3";X-SEMICOLON="1;2;3";X-TYPE=IMPORTANT:mailto:organizer@examp
              le.com
             END:VEVENT
             END:VCALENDAR
             """)
  end

  test "escaped characters in property value" do
    data = [
      vcalendar: [
        [
          vevent: [
            [
              description: {
                "text escaping \\ ; , \n \r\n \\n \" end",
                []
              }
            ]
          ]
        ]
      ]
    ]

    # note the ~S used here to disable escaping
    assert Calex.encode!(data) ==
             crlf(~S"""
             BEGIN:VCALENDAR
             BEGIN:VEVENT
             DESCRIPTION:text escaping \\ \; \, \n \n \\n " end
             END:VEVENT
             END:VCALENDAR
             """)
  end

  defp crlf(string) do
    string
    |> String.split("\n")
    |> Enum.join("\r\n")
  end
end
