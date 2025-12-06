#!/bin/bash
# Monitor NFSv2 network traffic

echo "Starting network monitoring for NFSv2 container..."
echo "Press 'q' to quit nload"
echo ""

docker exec -it nfsv2-vxworks nload eth0




