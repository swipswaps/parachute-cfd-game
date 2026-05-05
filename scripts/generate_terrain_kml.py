#!/usr/bin/env python3
"""
Generate KML file for Google Earth terrain export at specified location.

WHAT: Creates KML placemark with camera viewpoint for terrain capture
WHY:  Automates the process of defining terrain bounding boxes for export
MENTAL MODEL BEFORE: Manual Google Earth navigation and screenshot
MENTAL MODEL AFTER:  Script generates KML → open in Google Earth → export 3D
FAILURE MODE: Invalid coordinates → KML won't display correctly in Google Earth
VERIFIES WITH: Open generated .kml in Google Earth Pro, verify location and zoom

Source (Tier 2): Google KML 2.2 Reference - LookAt and Camera elements
  https://developers.google.com/kml/documentation/kmlreference#lookat
"""

import argparse
from lxml import etree

def generate_terrain_kml(lat, lon, radius, output_path, altitude=500):
    """
    Generate KML with camera viewpoint for terrain export.
    
    Args:
        lat: Latitude in decimal degrees (WGS84)
        lon: Longitude in decimal degrees (WGS84)
        radius: Approximate radius in meters for terrain area
        output_path: Output .kml file path
        altitude: Camera altitude in meters above ground
    
    MENTAL MODEL: KML LookAt defines viewpoint → Google Earth renders 3D tile set
    FAILURE MODE: radius too large (> 1km) → mesh too complex for CFD
    VERIFIES WITH: File created with valid KML structure
    
    Source (Tier 2): KML LookAt element specifies camera position and orientation
      https://developers.google.com/kml/documentation/kmlreference#lookat
    """
    
    # Create KML structure
    kml_ns = "http://www.opengis.net/kml/2.2"
    kml = etree.Element("{%s}kml" % kml_ns, nsmap={None: kml_ns})
    
    document = etree.SubElement(kml, "Document")
    etree.SubElement(document, "name").text = f"Terrain Export: {lat}, {lon}"
    
    # Create placemark with LookAt camera
    placemark = etree.SubElement(document, "Placemark")
    etree.SubElement(placemark, "name").text = f"CFD Terrain Area (r={radius}m)"
    
    # LookAt defines the camera viewpoint
    # Source: Google KML 2.2 spec - LookAt provides intuitive camera control
    lookat = etree.SubElement(placemark, "LookAt")
    etree.SubElement(lookat, "longitude").text = str(lon)
    etree.SubElement(lookat, "latitude").text = str(lat)
    etree.SubElement(lookat, "altitude").text = "0"
    etree.SubElement(lookat, "heading").text = "0"  # North
    etree.SubElement(lookat, "tilt").text = "45"  # 45° angle for 3D view
    etree.SubElement(lookat, "range").text = str(altitude)  # Distance from point
    etree.SubElement(lookat, "altitudeMode").text = "relativeToGround"
    
    # Point marker at center
    point = etree.SubElement(placemark, "Point")
    coordinates = etree.SubElement(point, "coordinates")
    coordinates.text = f"{lon},{lat},0"
    
    # Write KML file
    tree = etree.ElementTree(kml)
    tree.write(output_path, pretty_print=True, xml_declaration=True, encoding='utf-8')
    
    print(f"KML generated: {output_path}")
    print(f"Center: {lat}° N, {lon}° E")
    print(f"Radius: ~{radius}m")
    print(f"Camera altitude: {altitude}m")
    print("\nNext steps:")
    print(f"1. Open {output_path} in Google Earth Pro")
    print("2. Adjust view if needed (zoom, tilt)")
    print("3. File → Save → Save Place As... → COLLADA (.dae)")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generate KML for Google Earth terrain export"
    )
    parser.add_argument("--lat", type=float, required=True,
                        help="Latitude (decimal degrees, e.g., 37.7749)")
    parser.add_argument("--lon", type=float, required=True,
                        help="Longitude (decimal degrees, e.g., -122.4194)")
    parser.add_argument("--radius", type=float, default=300,
                        help="Approximate terrain radius in meters (default: 300)")
    parser.add_argument("--altitude", type=float, default=500,
                        help="Camera altitude in meters (default: 500)")
    parser.add_argument("--output", type=str, required=True,
                        help="Output KML file path")
    
    args = parser.parse_args()
    
    # Validate inputs
    if not (-90 <= args.lat <= 90):
        print("ERROR: Latitude must be between -90 and 90")
        exit(1)
    if not (-180 <= args.lon <= 180):
        print("ERROR: Longitude must be between -180 and 180")
        exit(1)
    if args.radius <= 0 or args.radius > 2000:
        print("WARNING: Radius should be 50-1000m for optimal CFD mesh size")
    
    generate_terrain_kml(args.lat, args.lon, args.radius, args.output, args.altitude)