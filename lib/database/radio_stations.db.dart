/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Musify is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Musify is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Musify, including how to contribute,
 *     please visit: https://github.com/gokadzev/Musify
 */

import 'package:musify/models/radio_model.dart';

List<RadioStation> radioStationsDB = [
  const RadioStation(
    id: 'r_cap_london',
    name: 'radio mirchi',
    image: 'https://liveradios.in/wp-content/uploads/RadioMirchi-logo.jpg',
    streamUrl: 'https://stream-284.surfernetwork.com/wgaznsmt92quv?zt=eyJhbGciOiJIUzI1NiJ9.eyJzdHJlYW0iOiJ3Z2F6bnNtdDkycXV2IiwiaG9zdCI6InN0cmVhbS0yODQuc3VyZmVybmV0d29yay5jb20iLCJydHRsIjo1LCJqdGkiOiJxTHN0NHRrRlM5Q3Z5M2tMUVNwVTRnIiwiaWF0IjoxNzkzOTU0NTM1LCJleHAiOjE3OTM5NTQ1OTV9.pTX0pY1o8lI04AcNMZDbLsIUTZaoHRyiKyaKMqOdc3U',
    genre: 'Pop',
  ),
  const RadioStation(
    id: 'r_top_hits',
    name: 'club fm',
    image: 'https://onlineradiofm.in/assets/image/radio/180/clubfmnewlogo.webp',
    streamUrl: 'https://ice31.securenetsystems.net/RADIOKERAL',
    genre: 'Pop',
  ),
  const RadioStation(
    id: 'r_bigfm',
    name: 'redFM',
    image: 'https://onlineradiofm.in/assets/image/radio/180/red-fm15.webp',
    streamUrl: 'https://stream-281.surfernetwork.com/9phrkb1e3v8uv?zt=eyJhbGciOiJIUzI1NiJ9.eyJzdHJlYW0iOiI5cGhya2IxZTN2OHV2IiwiaG9zdCI6InN0cmVhbS0yODEuc3VyZmVybmV0d29yay5jb20iLCJydHRsIjo1LCJqdGkiOiJrTXFlZ0czM1FzaUJrSVhUY05BOFVnIiwiaWF0IjoxNzkzOTU1Nzk1LCJleHAiOjE3OTM5NTU4NTV9.IQ-oZlDepLATGAjgGD11x--XIbjNOFL1j3sa-0R-62I',
    genre: 'Pop',
  ),
  const RadioStation(
    id: 'r_kissfm',
    name: 'radio mango',
    image: 'https://liveradios.in/wp-content/uploads/radiomango.jpg',
    streamUrl: 'https://strw3.openstream.co/1459?aw_0_1st.collectionid%3D4635%26stationId%3D4635%26publisherId%3D1483%26k%3D1793957098',
    genre: 'melody',
  ),
  const RadioStation(
    id: 'r_rockfm',
    name: 'tcr FM',
    image: 'https://liveradios.in/wp-content/uploads/airthrissur.jpg',
    streamUrl: 'https://d1cvqgmbcpg5yn.cloudfront.net/f70fdeca437dc326/f70fdeca437dc326.m3u8',
    genre: 'old songs',
  ),
  const RadioStation(
    id: 'r_radio1rock',
    name: 'arjith singh fm',
    image: 'https://liveradios.in/wp-content/uploads/arjitsingh.jpg',
    streamUrl: 'https://bhs.edge.mystreaming.net/uber/bollywoodaruitsingh/icecast.audio',
    genre: 'arjith singh tracks',
  ),
  const RadioStation(
    id: 'r_global_rnb',
    name: 'MY radio',
    image: 'https://hyacswinmpmdyxiyovcn.supabase.co/storage/v1/object/public/avatars/62f7aab5-4a55-4370-a094-437c5660e27e/1789636262289.jpeg',
    streamUrl: 'https://musify-api-331v.onrender.com/api/radio/stream',
    genre: 'R&B',
  ),
  const RadioStation(
    id: 'r_love_music_radio',
    name: 'Love Music Radio',
    image: 'https://static2.mytuner.mobi/media/tvos_radios/f4tz8QjdyU.png',
    streamUrl: 'https://radio2.reans.net/radio/8050/radio.mp3',
    genre: 'R&B',
  ),
  const RadioStation(
    id: 'r_powerhitz_lit',
    name: 'Powerhitz - Lit Hip Hop',
    image: 'https://powerhitz.com/images/menu/Lithhlogo.png',
    streamUrl: 'https://live.powerhitz.com/lit',
    genre: 'Hip Hop',
  ),
  const RadioStation(
    id: 'r_011fm_hiphop',
    name: '011.FM - Hip Hop Hits',
    image: 'https://static2.mytuner.mobi/media/tvos_radios/u9af7yyuprlu.png',
    streamUrl: 'https://listen.011fm.com/stream13',
    genre: 'Hip Hop',
  ),
  const RadioStation(
    id: 'r_phonk_radio',
    name: 'Phonk Radio',
    image: 'https://i.scdn.co/image/ab676161000051740e5f02df5be105222ceda8c0',
    streamUrl: 'https://stream.laut.fm/phonk',
    genre: 'Phonk',
  ),
  const RadioStation(
    id: 'r_technobase',
    name: 'Technobase.FM',
    image: 'https://kuasark.com/files/stations-logos/technobasefm.png',
    streamUrl: 'https://mp3.stream.tb-group.fm/tb.mp3',
    genre: 'Techno',
  ),
  const RadioStation(
    id: 'r_housetime',
    name: 'Housetime.FM',
    image: 'https://kuasark.com/files/stations-logos/housetimefm.png',
    streamUrl: 'https://mp3.stream.tb-group.fm/ht.mp3',
    genre: 'House',
  ),
  const RadioStation(
    id: 'r_trancebase',
    name: 'Trancebase.FM',
    image: 'https://kuasark.com/files/stations-logos/trancebasefm.png',
    streamUrl: 'https://mp3.stream.tb-group.fm/trb.mp3',
    genre: 'Trance',
  ),
  const RadioStation(
    id: 'r_lofi_radio',
    name: 'Lofi Radio',
    image: 'https://upload.wikimedia.org/wikipedia/en/f/f5/Lofi_Girl_logo_2024.jpg',
    streamUrl: 'https://play.streamafrica.net/lofiradio',
    genre: 'Lofi',
  ),
  const RadioStation(
    id: 'r_181fm_the_box',
    name: '181.FM - The Box Urban',
    image: 'https://cdn-profiles.tunein.com/s51095/images/logoq.jpg',
    streamUrl: 'https://listen.181fm.com/181-thebox_128k.mp3',
    genre: 'Hip Hop',
  ),
];
