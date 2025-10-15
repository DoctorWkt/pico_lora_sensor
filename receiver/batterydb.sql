-- Details of each battery: id, name, ADC value when reading 0V, X Volts,
-- ADC value when reading X volts
CREATE TABLE battery (
        id integer primary key,
        name text unique not null,
	adc_0V integer not null,
	XV real not null,
        adc_XV integer not null
);

-- Historical battery levels in volts and a Unix timestamp
CREATE TABLE histlevels (
        id integer not null,
	voltage real not null,
        timestamp integer not null
);
