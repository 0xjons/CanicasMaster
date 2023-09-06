// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

contract CarrerasDeCanicas {
    // Representa una canica con un identificador, nombre, color y enlace a IPFS
    struct Canica {
        uint256 id;
        string nombre;
        string color;
        string ipfsBaseLink; // Enlace base a IPFS para la imagen de la canica
    }

    // Representa una apuesta realizada por un apostador con una cantidad específica
    struct Apuesta {
        address payable apostador;
        uint256 cantidad;
    }

    // Representa una carrera con un identificador, estado y canica ganadora
    struct Carrera {
        uint256 id;
        bool activo;
        uint256 canicaGanadora;
    }

    // Array de canicas
    Canica[] public canicas;
    // Array de carreras
    Carrera[] public carreras;
    // Mapeo de apuestas por carrera y canica
    mapping(uint256 => mapping(uint256 => Apuesta[]))
        public apuestasPorCarreraYCanica;
    // Mapeo de balances por apostador
    mapping(address => uint256) public balances;
    // Dirección del propietario del contrato
    address public owner;
    // Comisión del propietario expresada en porcentaje
    uint256 public comisionOwner = 5;
    // Acumulado de comisiones del propietario
    uint256 public acumuladoOwner = 0;

    // Eventos para notificar acciones relevantes en el contrato
    event CanicaAgregada(
        uint256 id,
        string nombre,
        string color,
        string ipfsBaseLink
    );
    event ApuestaRealizada(
        address apostador,
        uint256 canicaId,
        uint256 carreraId,
        uint256 cantidad
    );
    event CarreraCreada(uint256 id);
    event CarreraFinalizada(uint256 id, uint256 canicaGanadora);
    event GananciasRetiradas(address apostador, uint256 cantidad);
    event ComisionCambiada(uint256 nuevaComision);

    // Constructor que establece al creador del contrato como propietario
    constructor() {
        owner = msg.sender;
    }

    // Modificador para restringir el acceso solo al propietario del contrato
    modifier soloOwner() {
        require(
            msg.sender == owner,
            "Solo el dueno puede llamar a esta funcion"
        );
        _;
    }

    /**
     * @dev Agrega una nueva canica al contrato.
     * @param _nombre Nombre de la canica.
     * @param _color Color de la canica.
     * @param _ipfsBaseLink Enlace base a IPFS para la imagen de la canica.
     */
    function agregarCanica(
        string memory _nombre,
        string memory _color,
        string memory _ipfsBaseLink
    ) public soloOwner {
        canicas.push(Canica(canicas.length, _nombre, _color, _ipfsBaseLink));
        emit CanicaAgregada(canicas.length, _nombre, _color, _ipfsBaseLink);
    }

    /**
     * @dev Crea una nueva carrera en el contrato.
     */
    function crearCarrera() public soloOwner {
        carreras.push(Carrera(carreras.length, true, 0));
        emit CarreraCreada(carreras.length);
    }

    /**
     * @dev Permite a un usuario apostar en una carrera y canica específica.
     * @param _canicaId Identificador de la canica.
     * @param _carreraId Identificador de la carrera.
     * @param _cantidad Cantidad apostada.
     */
    function apostar(
        uint256 _canicaId,
        uint256 _carreraId,
        uint256 _cantidad
    ) public payable {
        require(carreras[_carreraId].activo, "La carrera no esta activa");
        require(canicas.length > _canicaId, "Canica no valida");
        require(
            msg.value == _cantidad,
            "La cantidad enviada no coincide con la apuesta"
        );

        Apuesta memory nuevaApuesta = Apuesta({
            apostador: payable(msg.sender),
            cantidad: _cantidad
        });
        apuestasPorCarreraYCanica[_carreraId][_canicaId].push(nuevaApuesta);
        emit ApuestaRealizada(msg.sender, _canicaId, _carreraId, _cantidad);
    }

    /**
     * @dev Finaliza una carrera y determina la canica ganadora.
     * @param _carreraId Identificador de la carrera.
     * @param _canicaGanadora Identificador de la canica ganadora.
     */
    function finalizarCarrera(uint256 _carreraId, uint256 _canicaGanadora)
        public
        soloOwner
    {
        require(carreras[_carreraId].activo, "La carrera ya fue finalizada");
        carreras[_carreraId].activo = false;
        carreras[_carreraId].canicaGanadora = _canicaGanadora;

        uint256 pozoGanador = 0;
        uint256 pozoTotal = 0;

        for (uint256 i = 0; i < canicas.length; i++) {
            Apuesta[] memory apuestasCanica = apuestasPorCarreraYCanica[
                _carreraId
            ][i];
            for (uint256 j = 0; j < apuestasCanica.length; j++) {
                if (i == _canicaGanadora) {
                    pozoGanador += apuestasCanica[j].cantidad;
                }
                pozoTotal += apuestasCanica[j].cantidad;
            }
        }

        uint256 comision = (pozoTotal * comisionOwner) / 100;
        acumuladoOwner += comision;
        pozoTotal -= comision;

        Apuesta[] memory apuestasGanadoras = apuestasPorCarreraYCanica[
            _carreraId
        ][_canicaGanadora];
        for (uint256 i = 0; i < apuestasGanadoras.length; i++) {
            uint256 recompensa = (apuestasGanadoras[i].cantidad / pozoGanador) *
                pozoTotal;
            balances[apuestasGanadoras[i].apostador] += recompensa;
        }

        emit CarreraFinalizada(_carreraId, _canicaGanadora);
    }

    /**
     * @dev Permite a un usuario retirar sus ganancias.
     */
    function retirarGanancias() public {
        uint256 cantidad = balances[msg.sender];
        require(cantidad > 0, "No tienes ganancias para retirar");
        balances[msg.sender] = 0;
        payable(msg.sender).transfer(cantidad);
        emit GananciasRetiradas(msg.sender, cantidad);
    }

    /**
     * @dev Permite al dueño del contrato retirar las comisiones acumuladas.
     */
    function retirarComision() public soloOwner {
        uint256 cantidad = acumuladoOwner;
        require(cantidad > 0, "No hay comisiones para retirar");
        acumuladoOwner = 0;
        payable(msg.sender).transfer(cantidad);
    }

    /**
     * @dev Obtiene el enlace de la imagen de una canica en IPFS.
     * @param _canicaId Identificador de la canica.
     * @return Enlace completo a la imagen de la canica en IPFS.
     */
    function obtenerLinkImagenCanica(uint256 _canicaId)
        public
        view
        returns (string memory)
    {
        require(_canicaId < canicas.length, "Canica no valida");
        return
            string(
                abi.encodePacked(
                    canicas[_canicaId].ipfsBaseLink,
                    uint2str(_canicaId),
                    ".png"
                )
            );
    }

    /**
     * @dev Muestra los detalles de una canica, incluida la ruta completa de la imagen en IPFS.
     * @param _canicaId Identificador de la canica que se desea mostrar.
     * @return id Identificador de la canica.
     * @return nombre Nombre de la canica.
     * @return color Color de la canica.
     * @return ipfsLink Ruta completa de la imagen de la canica en IPFS.
     */
    function mostrarCanica(uint256 _canicaId)
        public
        view
        returns (
            uint256 id,
            string memory nombre,
            string memory color,
            string memory ipfsLink
        )
    {
        require(_canicaId < canicas.length, "Canica no valida");
        Canica memory canica = canicas[_canicaId];
        ipfsLink = string(
            abi.encodePacked(canica.ipfsBaseLink, uint2str(_canicaId), ".png")
        );
        return (canica.id, canica.nombre, canica.color, ipfsLink);
    }

    /**
     * @dev Función para cambiar la variable comisionOwner
     * @param nuevaComision Identificador de la nueva comisión para el dueño del contrato.
     */
    function cambiarComisionOwner(uint256 nuevaComision) public soloOwner {
        comisionOwner = nuevaComision;
        emit ComisionCambiada(nuevaComision);
    }

    /**
     * @dev Convierte un número entero sin signo (uint256) a su representación en cadena de caracteres (string).
     * @param _i El número entero sin signo que se desea convertir.
     * @return La representación en cadena de caracteres del número entero.
     */
    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        while (_i != 0) {
            bstr[--k] = bytes1(uint8(48 + (_i % 10)));
            _i /= 10;
        }
        return string(bstr);
    }
}

