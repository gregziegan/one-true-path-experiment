module SegmentTest exposing (..)

import Test exposing (..)
import Fuzz
import Expect
import Segment exposing (Segment(..))
import LowLevel.Command exposing (moveTo, lineTo, largestArc, clockwise, smallestArc, counterClockwise)
import Curve
import SubPath
import Vector2 as Vec2
import Geometry.Ellipse as Ellipse


(=>) =
    (,)


vec2 =
    Fuzz.map2 (,) (Fuzz.map toFloat Fuzz.int) (Fuzz.map toFloat Fuzz.int)


cleanFloat v =
    round (v * 1.0e12)
        |> toFloat
        |> (\v -> v * 1.0e-12)


cleanVec2 ( x, y ) =
    ( cleanFloat x, cleanFloat y )


segment : Fuzz.Fuzzer Segment
segment =
    Fuzz.frequency
        [ 1 => Fuzz.map2 LineSegment vec2 vec2
        , 1 => Fuzz.map3 Quadratic vec2 vec2 vec2
        , 1 => Fuzz.map4 Cubic vec2 vec2 vec2 vec2
        , 1
            => let
                direction =
                    Fuzz.frequency [ 1 => Fuzz.constant clockwise, 1 => Fuzz.constant counterClockwise ]

                arcFlag =
                    Fuzz.frequency [ 1 => Fuzz.constant largestArc, 1 => Fuzz.constant smallestArc ]

                xAngle =
                    Fuzz.floatRange 0 (2 * pi)
               in
                Fuzz.map4
                    (\start end radii direction arcFlag xAngle ->
                        Arc { start = start, end = end, radii = radii, direction = direction, arcFlag = arcFlag, xAxisRotate = xAngle }
                    )
                    vec2
                    vec2
                    (Fuzz.map (\( x, y ) -> ( max x 1, max y 1 )) vec2)
                    direction
                    |> Fuzz.andMap arcFlag
                    |> Fuzz.andMap xAngle
        ]


arcLengthParameterization =
    describe "arc length parameterization"
        [ test "f 2 with LineSegment (0,0) (4,0) is (2,0)" <|
            \_ ->
                LineSegment ( 0, 0 ) ( 4, 0 )
                    |> flip Segment.arcLengthParameterization 2
                    |> Expect.equal (Just ( 2, 0 ))
        , test "f 2 with LineSegment (0,0) (0,4) is (0,2)" <|
            \_ ->
                LineSegment ( 0, 0 ) ( 0, 4 )
                    |> flip Segment.arcLengthParameterization 2
                    |> Expect.equal (Just ( 0, 2 ))
        , test "f 2 with CubicSegment (0,0) (0,4) is (0,2)" <|
            \_ ->
                Cubic ( 0, 0 ) ( 0, 0 ) ( 4, 0 ) ( 4, 0 )
                    |> flip Segment.arcLengthParameterization 2
                    |> Expect.equal (Just ( 2, 0 ))
        , test "f 2 with Ellipse (1,0) (0,1) is ( cos (pi / 4), sin (pi / 4))" <|
            \_ ->
                let
                    arc =
                        { start = ( 1, 0 ), end = ( -1, 0 ), radii = ( 1, 1 ), xAxisRotate = 0, arcFlag = largestArc, direction = counterClockwise }

                    lines =
                        Segment.toChordLengths 50 (Arc arc)

                    _ =
                        List.map (uncurry Vec2.distance) lines
                            |> List.scanl (+) 0
                            |> List.drop 1
                            |> List.filter (\v -> v <= pi / 2)
                            |> List.map2 (,) lines
                            |> List.reverse
                            |> List.head
                in
                    Arc arc
                        |> flip Segment.arcLengthParameterization (pi / 2)
                        |> Maybe.map cleanVec2
                        |> Expect.equal (Just ( 0, 1 ))
        ]


arc =
    let
        direction =
            Fuzz.frequency [ 1 => Fuzz.constant clockwise, 1 => Fuzz.constant counterClockwise ]

        arcFlag =
            Fuzz.frequency [ 1 => Fuzz.constant largestArc, 1 => Fuzz.constant smallestArc ]

        xAngle =
            let
                factor =
                    2
            in
                Fuzz.map (\k -> toFloat k * (pi / 2)) (Fuzz.intRange 0 2)
    in
        Fuzz.map5
            (\center endAngle startAngle radii direction arcFlag xAngle ->
                Arc (Ellipse.centerToEndpoint { center = center, deltaTheta = endAngle, startAngle = startAngle, radii = radii, xAxisRotate = xAngle })
            )
            (Fuzz.map (\( x, y ) -> ( max x 1, max y 1 )) vec2)
            xAngle
            xAngle
            (Fuzz.map (\( x, y ) -> ( max x 1, max y 1 )) vec2)
            direction
            |> Fuzz.andMap arcFlag
            |> Fuzz.andMap xAngle


reverse =
    describe "reverse segments"
        [ fuzz segment "reverse << reverse = identity" <|
            \s ->
                s
                    |> Segment.reverse
                    |> Segment.reverse
                    |> Expect.equal s
        , fuzz (Fuzz.tuple ( vec2, vec2 )) "reverse line segment does not change the segment's length" <|
            \( start, end ) ->
                let
                    s =
                        LineSegment start end
                in
                    s
                        |> Segment.reverse
                        |> Segment.length
                        |> Expect.equal (Segment.length s)
        , fuzz (Fuzz.tuple3 ( vec2, vec2, vec2 )) "reverse quadratic segment does not change the segment's length" <|
            \( start, c1, end ) ->
                let
                    s =
                        Quadratic start c1 end
                in
                    s
                        |> Segment.reverse
                        |> Segment.length
                        |> Expect.equal (Segment.length s)
        , fuzz (Fuzz.tuple4 ( vec2, vec2, vec2, vec2 )) "reverse cubic segment does not change the segment's length" <|
            \( start, c1, c2, end ) ->
                let
                    s =
                        Cubic start c1 c2 end
                in
                    s
                        |> Segment.reverse
                        |> Segment.length
                        |> Expect.equal (Segment.length s)
        , fuzz arc "reverse arc segment does not change the segment's length" <|
            \s ->
                let
                    _ =
                        ()

                    {-
                       given =
                           s
                               |> Segment.reverse
                               |> Segment.length

                       expected =
                           Segment.length s
                       abs (given - expected)
                           |> Expect.atMost 1.0e-6
                    -}
                    given =
                        Segment.at 0.5 (Segment.reverse s)

                    expected =
                        Segment.at 0.5 s

                    difference =
                        Vec2.distance given expected
                in
                    if difference > 1.0 then
                        let
                            _ =
                                Debug.log "given, expected" ( given, expected, s, Segment.reverse s )
                        in
                            difference
                                |> Expect.atMost 1.0e-6
                    else
                        difference
                            |> Expect.atMost 1.0e-6
          {-
             , fuzz segment "reverse does not change a segment's length" <|
                 \s ->
                     s
                         |> Debug.log "segment"
                         |> Segment.reverse
                         |> Segment.length
                         |> Debug.log "segment length"
                         |> Expect.equal (Debug.log "expected length" <| Segment.length s)
          -}
        ]


segments =
    [ "line" => LineSegment ( 0, 42 ) ( 42, 0 )
    , "quadratic" => Quadratic ( 0, 42 ) ( 0, 0 ) ( 42, 0 )
    , "cubic" => Cubic ( 0, 42 ) ( 0, 0 ) ( 0, 0 ) ( 42, 0 )
    , "arc" => Arc { start = ( 0, 42 ), end = ( 42, 0 ), radii = ( 1, 1 ), xAxisRotate = 0, arcFlag = largestArc, direction = clockwise }
    ]


startAndEnd =
    let
        createTests name value =
            [ test (name ++ "- first point is (0, 42)") <|
                \_ ->
                    Segment.firstPoint value
                        |> Expect.equal ( 0, 42 )
            , test (name ++ "- final point is (42, 0)") <|
                \_ ->
                    Segment.finalPoint value
                        |> Expect.equal ( 42, 0 )
            ]
    in
        describe "start and end points" <|
            List.concatMap (uncurry createTests) segments


angle =
    describe "angle tests"
        [ test "angle is pi / 2" <|
            \_ ->
                Segment.angle (LineSegment ( 0, 0 ) ( 100, 0 )) (LineSegment ( 0, 0 ) ( 0, 100 ))
                    |> Expect.equal (pi / 2)
        , test "angle is -pi / 2" <|
            \_ ->
                Segment.angle (LineSegment ( 0, 0 ) ( 0, 100 )) (LineSegment ( 0, 0 ) ( 100, 0 ))
                    |> Expect.equal (pi / -2)
        , test "angle is pi" <|
            \_ ->
                Segment.angle (LineSegment ( 0, 0 ) ( 100, 0 )) (LineSegment ( 100, 0 ) ( 0, 0 ))
                    |> Expect.equal (pi)
        , test "angle is 0" <|
            \_ ->
                Segment.angle (LineSegment ( 0, 0 ) ( 100, 0 )) (LineSegment ( 0, 0 ) ( 100, 0 ))
                    |> Expect.equal 0
        ]


toSegments =
    describe "conversion from and to segments"
        [ test "conversion from linear produces correctly ordered result" <|
            \_ ->
                Curve.linear [ ( 0, 0 ), ( 100, 0 ), ( 100, 100 ) ]
                    |> SubPath.toSegments
                    |> Expect.equal [ LineSegment ( 0, 0 ) ( 100, 0 ), LineSegment ( 100, 0 ) ( 100, 100 ) ]
        , test "conversion from subpath produces correctly ordered result" <|
            \_ ->
                SubPath.subpath (moveTo ( 0, 0 )) [ lineTo [ ( 100, 0 ), ( 100, 100 ) ] ]
                    |> SubPath.toSegments
                    |> Expect.equal [ LineSegment ( 0, 0 ) ( 100, 0 ), LineSegment ( 100, 0 ) ( 100, 100 ) ]
        , test "conversion from drawto to segment produces correctly ordered result" <|
            \_ ->
                lineTo [ ( 100, 0 ), ( 100, 100 ) ]
                    |> Segment.toSegment (LineSegment ( 0, 0 ) ( 0, 0 ))
                    |> Expect.equal [ LineSegment ( 0, 0 ) ( 100, 0 ), LineSegment ( 100, 0 ) ( 100, 100 ) ]
        ]
